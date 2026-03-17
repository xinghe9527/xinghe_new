#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
Vidu 自动化 API 服务器
提供本地 HTTP 接口供 Flutter 调用

功能：
- 异步任务提交（不阻塞接口）
- 浏览器窗口显隐控制
- 任务状态查询
- 长时间运行的后台服务

启动方式：
    python python_backend/web_automation/api_server.py
    或
    uvicorn api_server:app --host 127.0.0.1 --port 8123
"""

import sys
import os
import io
import json
import asyncio
import subprocess
from typing import Optional, Dict, Any
from datetime import datetime
from enum import Enum

from fastapi import FastAPI, HTTPException, BackgroundTasks
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import uvicorn

# Windows 窗口控制
try:
    import pygetwindow as gw
    WINDOW_CONTROL_AVAILABLE = True
except ImportError:
    WINDOW_CONTROL_AVAILABLE = False
    print("⚠️  警告: pygetwindow 未安装，窗口控制功能将不可用")

# 确保标准输出使用 UTF-8 编码
try:
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
except:
    pass

# ============================================================================
# 安全打印（stdout 管道断裂时不抛异常）
# ============================================================================
_original_print = print

def _safe_print(*args, **kwargs):
    """print() 的安全替代：当 stdout 管道断裂时（如 Dart 重启），静默忽略错误"""
    try:
        _original_print(*args, **kwargs)
    except (OSError, IOError, ValueError):
        pass  # stdout 不可写时跳过，不影响任务执行

print = _safe_print

# ============================================================================
# 配置
# ============================================================================

# 获取项目根目录的绝对路径
if getattr(sys, 'frozen', False):
    SCRIPT_DIR = os.path.dirname(os.path.abspath(sys.executable))
    PROJECT_ROOT = SCRIPT_DIR
else:
    SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
    PROJECT_ROOT = os.path.dirname(os.path.dirname(SCRIPT_DIR))

# Python 可执行文件路径
PYTHON_EXECUTABLE = sys.executable  # 使用当前 Python 解释器

# auto_vidu.py 脚本路径
AUTO_VIDU_SCRIPT = os.path.join(SCRIPT_DIR, 'auto_vidu.py')
AUTO_VIDU_COMPLETE_SCRIPT = os.path.join(SCRIPT_DIR, 'auto_vidu_complete.py')  # ✅ 完整版脚本
AUTO_JIMENG_SCRIPT = os.path.join(SCRIPT_DIR, 'auto_jimeng.py')  # ✅ 即梦自动化脚本

# ============================================================================
# 数据模型
# ============================================================================

class TaskStatus(str, Enum):
    """任务状态枚举"""
    PENDING = "pending"      # 等待执行
    RUNNING = "running"      # 执行中
    SUCCESS = "success"      # 成功
    FAILED = "failed"        # 失败
    CANCELLED = "cancelled"  # 已取消


class GenerateRequest(BaseModel):
    """视频生成请求"""
    prompt: str
    platform: str = "vidu"  # 预留：支持多平台


class TaskResponse(BaseModel):
    """任务响应"""
    task_id: str
    status: TaskStatus
    message: str
    created_at: str
    prompt: Optional[str] = None
    task_ids: Optional[list] = None  # 批量模式时包含所有 task_id


class TaskStatusResponse(BaseModel):
    """任务状态响应"""
    task_id: str
    status: TaskStatus
    message: str
    created_at: str
    updated_at: str
    prompt: Optional[str] = None
    result: Optional[Dict[str, Any]] = None
    error: Optional[str] = None


class BrowserControlResponse(BaseModel):
    """浏览器控制响应"""
    success: bool
    message: str
    window_found: bool = False


# ============================================================================
# 全局状态管理
# ============================================================================

class TaskManager:
    """任务管理器"""
    
    def __init__(self):
        self.tasks: Dict[str, Dict[str, Any]] = {}
        self.current_process: Optional[subprocess.Popen] = None
        self.browser_window_title: Optional[str] = None
        
    def create_task(
        self, 
        task_id: str, 
        prompt: str, 
        platform: str = "vidu",
        tool_type: Optional[str] = None,
        payload: Optional[Dict[str, Any]] = None
    ) -> Dict[str, Any]:
        """创建新任务"""
        task = {
            "task_id": task_id,
            "status": TaskStatus.PENDING,
            "message": "任务已创建，等待执行",  # ✅ 添加 message 字段
            "prompt": prompt,
            "platform": platform,
            "tool_type": tool_type,
            "payload": payload,
            "created_at": datetime.now().isoformat(),
            "updated_at": datetime.now().isoformat(),
            "result": None,
            "error": None,
        }
        self.tasks[task_id] = task
        return task
    
    def update_task(self, task_id: str, **kwargs):
        """更新任务状态"""
        if task_id in self.tasks:
            self.tasks[task_id].update(kwargs)
            self.tasks[task_id]["updated_at"] = datetime.now().isoformat()
    
    def get_task(self, task_id: str) -> Optional[Dict[str, Any]]:
        """获取任务信息"""
        return self.tasks.get(task_id)
    
    def get_all_tasks(self) -> Dict[str, Dict[str, Any]]:
        """获取所有任务"""
        return self.tasks


# 全局任务管理器实例
task_manager = TaskManager()

# ============================================================================
# FastAPI 应用
# ============================================================================

app = FastAPI(
    title="Vidu 自动化 API",
    description="本地微服务，供 Flutter 调用 Vidu 自动化功能",
    version="1.0.0",
)

# 添加 CORS 中间件（允许 Flutter 跨域访问）
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # 生产环境建议限制为具体域名
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ============================================================================
# 后台任务执行
# ============================================================================

# Vidu 自动化单例（所有任务共享同一个浏览器）
_vidu_auto_instance = None
_vidu_auto_lock = None
_vidu_poll_lock = None  # Vidu 轮询锁（因为没有 history_id，poll 必须串行）

# ✅ 持久线程池：确保所有 Playwright 操作在同一个线程上执行
# Playwright 的 page 对象绑定创建线程，submit 和 poll 必须在同一线程
import concurrent.futures
_vidu_thread_pool = concurrent.futures.ThreadPoolExecutor(max_workers=1, thread_name_prefix='vidu_playwright')

def _get_vidu_lock():
    """延迟创建 Vidu 浏览器锁（保护 submit 阶段）"""
    global _vidu_auto_lock
    if _vidu_auto_lock is None:
        _vidu_auto_lock = asyncio.Lock()
    return _vidu_auto_lock

def _get_vidu_poll_lock():
    """延迟创建 Vidu 轮询锁（保护 poll 阶段，因为 Vidu 无法按任务 ID 区分结果）"""
    global _vidu_poll_lock
    if _vidu_poll_lock is None:
        _vidu_poll_lock = asyncio.Lock()
    return _vidu_poll_lock


async def execute_vidu_batch_automation(
    task_ids: list,
    prompt: str,
    save_path: Optional[str],
    aspect_ratio: Optional[str],
    resolution: Optional[str],
    duration: Optional[str],
    tool_type: Optional[str],
    model: Optional[str],
    reference_file: Optional[str],
    character_name: Optional[str],
    max_wait: int,
    batch_count: int,
    segments: list = None,
):
    """
    Vidu 批量生成：一次填写提示词 + 点 N 次创作，每个任务独立轮询。
    避免在网页上设置数量（非会员会弹充值弹窗）。
    """
    try:
        # 标记所有任务为 RUNNING
        for tid in task_ids:
            task_manager.update_task(tid, status=TaskStatus.RUNNING)
        
        print(f"\n{'='*60}", flush=True)
        print(f"  🚀 批量执行 Vidu 任务 (×{batch_count}): {task_ids}", flush=True)
        print(f"  📝 提示词: {prompt}", flush=True)
        print(f"{'='*60}\n", flush=True)
        
        # ============================================================
        # 阶段1：一次提交，点 N 次创作
        # ============================================================
        lock = _get_vidu_lock()
        async with lock:
            def _run_batch_submit():
                from auto_vidu_v2 import ViduAutomation
                global _vidu_auto_instance
                
                for attempt in range(2):
                    try:
                        if _vidu_auto_instance is None or not _vidu_auto_instance._started:
                            _vidu_auto_instance = ViduAutomation()
                            if not _vidu_auto_instance.start():
                                raise Exception("无法启动 Vidu 浏览器")
                        
                        auto = _vidu_auto_instance
                        if not auto.check_login():
                            raise Exception("Vidu 未登录")
                        
                        return auto.submit_generate(
                            prompt=prompt,
                            tool_type=tool_type or 'text2video',
                            model=model,
                            aspect_ratio=aspect_ratio,
                            resolution=resolution,
                            duration=duration,
                            reference_file=reference_file,
                            character_name=character_name,
                            count=batch_count,
                            segments=segments,
                        )
                    except Exception as e:
                        error_msg = str(e)
                        if any(kw in error_msg for kw in [
                            'browser has been closed', 'cannot switch to a different thread',
                            'Connection refused', 'target closed', 'Session closed',
                        ]):
                            print(f"   ⚠️  浏览器断开 (尝试 {attempt+1}/2): {error_msg[:80]}")
                            try:
                                if _vidu_auto_instance:
                                    _vidu_auto_instance.stop()
                            except:
                                pass
                            _vidu_auto_instance = None
                            if attempt == 0:
                                continue
                        raise
            
            loop = asyncio.get_event_loop()
            submit_result = await loop.run_in_executor(_vidu_thread_pool, _run_batch_submit)
        
        if not submit_result.get('success'):
            error_msg = submit_result.get('error', '提交失败')
            for tid in task_ids:
                task_manager.update_task(tid, status=TaskStatus.FAILED, error=error_msg)
            return
        
        # 提取批量结果
        batch_results = submit_result.get('batch_results', [])
        if not batch_results:
            # 兼容单任务返回格式
            batch_results = [{
                'task_key': submit_result.get('task_key', ''),
                'creation_id': submit_result.get('creation_id', ''),
                'initial_video_count': submit_result.get('initial_video_count', 0),
            }]
        
        print(f"   ✅ 批量提交完成: {len(batch_results)} 个任务", flush=True)
        
        # ============================================================
        # 阶段2：并行轮询每个任务
        # ============================================================
        async def _poll_single_task(tid, br, index):
            """轮询单个任务"""
            cid = br.get('creation_id', '')
            task_key = br.get('task_key', '')
            ivc = br.get('initial_video_count', 0)
            
            # 生成保存路径
            sp = None
            if save_path:
                base, ext = os.path.splitext(save_path)
                sp = f"{base}_{index}{ext}" if index > 0 else save_path
                # ✅ 验证保存路径
                try:
                    sp_dir = os.path.dirname(sp)
                    if sp_dir:
                        os.makedirs(sp_dir, exist_ok=True)
                except OSError:
                    downloads_dir = os.path.join(SCRIPT_DIR, 'downloads')
                    os.makedirs(downloads_dir, exist_ok=True)
                    sp = os.path.join(downloads_dir, f'{tid}.mp4')
            else:
                downloads_dir = os.path.join(SCRIPT_DIR, 'downloads')
                os.makedirs(downloads_dir, exist_ok=True)
                sp = os.path.join(downloads_dir, f'{tid}.mp4')
            
            print(f"   🚀 [{tid}] 开始轮询 (creation_id={cid or '无'})", flush=True)
            
            def _do_poll():
                global _vidu_auto_instance
                auto = _vidu_auto_instance
                if auto is None:
                    raise Exception("Vidu 自动化实例丢失")
                return auto.poll_result(
                    task_key=task_key,
                    initial_video_count=ivc,
                    max_wait=max_wait,
                    save_path=sp,
                    creation_id=cid,
                )
            
            result = await loop.run_in_executor(_vidu_thread_pool, _do_poll)
            
            if result.get('success'):
                task_manager.update_task(
                    tid,
                    status=TaskStatus.SUCCESS,
                    result={
                        'success': True,
                        'local_video_path': sp,
                        'video_url': result.get('video_url', ''),
                        'task_key': task_key,
                        'message': 'Vidu 视频生成成功',
                    },
                    message="Vidu 视频生成成功",
                )
                print(f"✅ Vidu 批量任务成功: {tid}", flush=True)
            else:
                error_msg = result.get('error', '未知错误')
                task_manager.update_task(tid, status=TaskStatus.FAILED, error=error_msg)
                print(f"❌ Vidu 批量任务失败: {tid} | {error_msg}", flush=True)
        
        # 启动并行轮询
        poll_tasks = []
        for i, (tid, br) in enumerate(zip(task_ids, batch_results)):
            poll_tasks.append(_poll_single_task(tid, br, i))
        
        # 如果任务数量 > 批量结果数量，标记多余的为失败
        for tid in task_ids[len(batch_results):]:
            task_manager.update_task(tid, status=TaskStatus.FAILED, error="批量提交时点击创作失败")
        
        await asyncio.gather(*poll_tasks)
        
    except Exception as e:
        error_msg = f"批量执行异常: {str(e)}"
        import traceback
        traceback.print_exc()
        for tid in task_ids:
            t = task_manager.get_task(tid)
            if t and t.get('status') in [TaskStatus.PENDING, TaskStatus.RUNNING]:
                task_manager.update_task(tid, status=TaskStatus.FAILED, error=error_msg)


async def execute_vidu_automation(
    task_id: str, 
    prompt: str, 
    save_path: Optional[str] = None,
    aspect_ratio: Optional[str] = None,
    resolution: Optional[str] = None,
    duration: Optional[str] = None,
    tool_type: Optional[str] = 'text2video',
    model: Optional[str] = None,
    reference_file: Optional[str] = None,
    character_name: Optional[str] = None,
    max_wait: int = 900,
    segments: list = None,
):
    """
    后台异步执行 Vidu 自动化（并发模式）
    
    锁只保护 UI 操作（提交生成），轮询结果不需要锁。
    多个任务可以同时在后台等待生成结果。
    """
    try:
        task_manager.update_task(task_id, status=TaskStatus.RUNNING)
        
        print(f"\n{'='*60}", flush=True)
        print(f"  🚀 开始执行 Vidu 任务: {task_id}", flush=True)
        print(f"  📝 提示词: {prompt}", flush=True)
        if save_path:
            print(f"  📁 保存路径: {save_path}", flush=True)
        print(f"  tool_type: {tool_type}, model: {model}", flush=True)
        print(f"{'='*60}\n", flush=True)
        
        if save_path is None:
            downloads_dir = os.path.join(SCRIPT_DIR, 'downloads')
            os.makedirs(downloads_dir, exist_ok=True)
            save_path = os.path.join(downloads_dir, f'{task_id}.mp4')
        else:
            # ✅ 验证 save_path 有效性（提前发现 Windows 路径问题）
            try:
                save_dir = os.path.dirname(save_path)
                if save_dir:
                    os.makedirs(save_dir, exist_ok=True)
            except OSError as path_err:
                print(f"  ⚠️  保存路径无效: {save_path}\n  错误: {path_err}", flush=True)
                # 回退到默认路径
                downloads_dir = os.path.join(SCRIPT_DIR, 'downloads')
                os.makedirs(downloads_dir, exist_ok=True)
                save_path = os.path.join(downloads_dir, f'{task_id}.mp4')
                print(f"  📁 已回退到默认路径: {save_path}", flush=True)
        
        import concurrent.futures
        
        # ============================================================
        # 阶段1：提交生成（需要浏览器锁）
        # ============================================================
        lock = _get_vidu_lock()
        print(f"   🔒 [{task_id}] 等待 Vidu 浏览器锁（提交阶段）...", flush=True)
        
        async with lock:
            print(f"   🔓 [{task_id}] 获取到 Vidu 浏览器锁", flush=True)
            
            def _run_submit():
                from auto_vidu_v2 import ViduAutomation
                
                global _vidu_auto_instance
                
                # ✅ 自动恢复：最多重试2次（第一次检测到浏览器死亡，重建后重试）
                for attempt in range(2):
                    try:
                        if _vidu_auto_instance is None or not _vidu_auto_instance._started:
                            _vidu_auto_instance = ViduAutomation()
                            if not _vidu_auto_instance.start():
                                raise Exception("无法启动 Vidu 浏览器，请先登录")
                        
                        auto = _vidu_auto_instance
                        
                        if not auto.check_login():
                            raise Exception("Vidu 未登录，请先运行: python open_browser_for_login.py vidu")
                        
                        # 只提交生成，不等待结果
                        submit_result = auto.submit_generate(
                            prompt=prompt,
                            tool_type=tool_type or 'text2video',
                            model=model,
                            aspect_ratio=aspect_ratio,
                            resolution=resolution,
                            duration=duration,
                            reference_file=reference_file,
                            character_name=character_name,
                            segments=segments,
                        )
                        
                        # ✅ submit_generate 内部吞掉异常返回 dict，需要手动检查浏览器断连
                        if not submit_result.get('success'):
                            err = submit_result.get('error', '')
                            browser_keywords = [
                                'browser has been closed',
                                'Target page, context or browser has been closed',
                                'cannot switch to a different thread',
                                'Connection refused', 'not connected',
                                'target closed', 'Session closed',
                            ]
                            if any(kw in err for kw in browser_keywords):
                                raise Exception(err)  # 抛出让重试逻辑处理
                        
                        return submit_result
                        
                    except Exception as e:
                        error_msg = str(e)
                        # ✅ 检测浏览器已关闭/线程已死的错误，自动重建实例
                        if any(keyword in error_msg for keyword in [
                            'cannot switch to a different thread',
                            'browser has been closed',
                            'Target page, context or browser has been closed',
                            'Connection refused',
                            'not connected',
                            'target closed',
                            'Session closed',
                        ]):
                            print(f"   ⚠️  检测到浏览器已断开（尝试 {attempt + 1}/2）: {error_msg[:80]}")
                            print(f"   🔄 自动重建浏览器实例...")
                            # 安全清理旧实例
                            try:
                                if _vidu_auto_instance is not None:
                                    _vidu_auto_instance.stop()
                            except:
                                pass
                            _vidu_auto_instance = None
                            
                            if attempt == 0:
                                continue  # 重试
                            else:
                                raise Exception(f"浏览器重建后仍然失败: {error_msg}")
                        else:
                            raise  # 其他错误直接抛出
            
            loop = asyncio.get_event_loop()
            # ✅ 使用全局持久线程池，确保 Playwright 操作在固定线程上
            submit_result = await loop.run_in_executor(_vidu_thread_pool, _run_submit)
        
        print(f"   🔒 [{task_id}] Vidu 浏览器锁已释放（提交完成）", flush=True)
        
        if not submit_result.get('success'):
            error_message = submit_result.get('error', '提交失败')
            task_manager.update_task(task_id, status=TaskStatus.FAILED, error=error_message)
            print(f"❌ Vidu 任务提交失败: {task_id}\n错误: {error_message}", flush=True)
            return
        
        task_key = submit_result.get('task_key', '')
        initial_video_count = submit_result.get('initial_video_count', 0)
        creation_id = submit_result.get('creation_id', '')
        print(f"   ✅ [{task_id}] 提交成功，task_key={task_key}, creation_id={creation_id or '(无)'}", flush=True)
        
        # ============================================================
        # 阶段2：轮询结果
        # 有 creation_id 时：按 ID 精准匹配视频 URL，可并行轮询（无需锁）
        # 无 creation_id 时：回退到 DOM 计数模式，需要 poll 锁串行
        # ============================================================
        
        def _run_poll():
            global _vidu_auto_instance
            auto = _vidu_auto_instance
            if auto is None:
                raise Exception("Vidu 自动化实例丢失")
            
            result = auto.poll_result(
                task_key=task_key,
                initial_video_count=initial_video_count,
                max_wait=max_wait,
                save_path=save_path,
                creation_id=creation_id,
            )
            return result
        
        loop = asyncio.get_event_loop()
        
        if creation_id:
            # ✅ 有 creation_id：直接并行轮询，无需锁
            print(f"   🚀 [{task_id}] 使用 ID 匹配模式，无需轮询锁（可并行）", flush=True)
            result = await loop.run_in_executor(_vidu_thread_pool, _run_poll)
        else:
            # ⚠️ 无 creation_id：回退到串行模式
            poll_lock = _get_vidu_poll_lock()
            print(f"   ⏳ [{task_id}] 无 creation_id，使用串行轮询锁...", flush=True)
            async with poll_lock:
                print(f"   🔓 [{task_id}] 获取到轮询锁", flush=True)
                result = await loop.run_in_executor(_vidu_thread_pool, _run_poll)
            print(f"   🔒 [{task_id}] 轮询锁已释放", flush=True)
        
        if result.get('success'):
            task_manager.update_task(
                task_id,
                status=TaskStatus.SUCCESS,
                result={
                    'success': True,
                    'local_video_path': save_path,
                    'video_url': result.get('video_url', ''),
                    'task_key': result.get('task_key', ''),
                    'message': 'Vidu 视频生成成功',
                },
                message="Vidu 视频生成成功",
            )
            print(f"✅ Vidu 任务成功: {task_id}", flush=True)
        else:
            error_message = result.get('error', '未知错误')
            task_manager.update_task(
                task_id,
                status=TaskStatus.FAILED,
                error=error_message,
            )
            print(f"❌ Vidu 任务失败: {task_id}\n错误: {error_message}", flush=True)
    
    except asyncio.CancelledError:
        task_manager.update_task(task_id, status=TaskStatus.CANCELLED, error="任务被用户取消")
        print(f"⚠️  Vidu 任务取消: {task_id}", flush=True)
    except Exception as e:
        error_message = f"执行异常: {str(e)}"
        task_manager.update_task(task_id, status=TaskStatus.FAILED, error=error_message)
        import traceback
        print(f"❌ Vidu 任务异常: {task_id}\n{error_message}", flush=True)
        traceback.print_exc()
        import sys; sys.stdout.flush(); sys.stderr.flush()
    finally:
        task_manager.current_process = None


# ============================================================================
# 即梦自动化执行（常驻浏览器实例 + 任务队列）
# ============================================================================

# 即梦自动化单例（所有任务共享同一个浏览器连接）
_jimeng_auto_instance = None
_jimeng_auto_lock = asyncio.Lock() if 'asyncio' in dir() else None
# ✅ 即梦也使用持久线程池
_jimeng_thread_pool = concurrent.futures.ThreadPoolExecutor(max_workers=1, thread_name_prefix='jimeng_playwright')

def _get_jimeng_lock():
    """延迟创建锁（避免在模块加载时创建）"""
    global _jimeng_auto_lock
    if _jimeng_auto_lock is None:
        _jimeng_auto_lock = asyncio.Lock()
    return _jimeng_auto_lock

async def _get_jimeng_auto():
    """获取或创建即梦自动化实例（单例）"""
    global _jimeng_auto_instance
    
    if _jimeng_auto_instance is not None and _jimeng_auto_instance._started:
        return _jimeng_auto_instance
    
    # 在线程池中启动（Playwright 是同步的）
    import concurrent.futures
    
    def _start_jimeng():
        from auto_jimeng import JimengAutomation
        auto = JimengAutomation()
        if auto.start():
            return auto
        return None
    
    loop = asyncio.get_event_loop()
    # ✅ 使用持久线程池
    _jimeng_auto_instance = await loop.run_in_executor(_jimeng_thread_pool, _start_jimeng)
    
    return _jimeng_auto_instance

async def execute_jimeng_automation(
    task_id: str,
    prompt: str,
    save_path: Optional[str] = None,
    aspect_ratio: Optional[str] = None,
    resolution: Optional[str] = None,
    duration: Optional[str] = None,
    tool_type: Optional[str] = 'video_gen',
    model: Optional[str] = None,
    mode: Optional[str] = None,
    reference_file: Optional[str] = None,
):
    """
    后台异步执行即梦自动化（并发模式）
    
    锁只保护 UI 操作（提交生成），轮询结果不需要锁。
    多个任务可以同时在后台等待生成结果。
    """
    try:
        task_manager.update_task(task_id, status=TaskStatus.RUNNING)
        
        print(f"\n{'='*60}")
        print(f"  🚀 开始执行即梦任务: {task_id}")
        print(f"  📝 提示词: {prompt}")
        if save_path:
            print(f"  📁 保存路径: {save_path}")
        print(f"{'='*60}\n")
        
        if save_path is None:
            downloads_dir = os.path.join(SCRIPT_DIR, 'downloads')
            os.makedirs(downloads_dir, exist_ok=True)
            save_path = os.path.join(downloads_dir, f'{task_id}.mp4')
        
        import concurrent.futures
        
        # ============================================================
        # 阶段1：提交生成（需要浏览器锁）
        # ============================================================
        lock = _get_jimeng_lock()
        print(f"   🔒 [{task_id}] 等待浏览器锁（提交阶段）...")
        
        history_id = ''
        
        async with lock:
            print(f"   🔓 [{task_id}] 获取到浏览器锁")
            
            def _run_submit():
                from auto_jimeng import JimengAutomation
                
                global _jimeng_auto_instance
                
                # ✅ 自动恢复：最多重试2次（第一次检测到浏览器死亡，重建后重试）
                for attempt in range(2):
                    try:
                        if _jimeng_auto_instance is None or not _jimeng_auto_instance._started:
                            _jimeng_auto_instance = JimengAutomation()
                            if not _jimeng_auto_instance.start():
                                raise Exception("无法启动即梦浏览器，请先登录")
                        
                        auto = _jimeng_auto_instance
                        
                        if not auto.check_login():
                            raise Exception("即梦未登录，请先运行: python open_browser_for_login.py jimeng")
                        
                        dur = int(''.join(filter(str.isdigit, str(duration)))) if duration else 5
                        
                        # 只提交生成，不等待结果
                        submit_result = auto.submit_generate(
                            prompt=prompt,
                            model=model or 'seedance-2.0-fast',
                            tool_type=tool_type or 'video_gen',
                            mode=mode,
                            aspect_ratio=aspect_ratio or '16:9',
                            resolution=resolution or '720p',
                            duration=dur,
                            reference_file=reference_file,
                        )
                        
                        return submit_result
                        
                    except Exception as e:
                        error_msg = str(e)
                        # ✅ 检测浏览器已关闭/线程已死的错误，自动重建实例
                        if any(keyword in error_msg for keyword in [
                            'cannot switch to a different thread',
                            'browser has been closed',
                            'Target page, context or browser has been closed',
                            'Connection refused',
                            'not connected',
                            'target closed',
                            'Session closed',
                        ]):
                            print(f"   ⚠️  检测到浏览器已断开（尝试 {attempt + 1}/2）: {error_msg[:80]}")
                            print(f"   🔄 自动重建浏览器实例...")
                            # 安全清理旧实例
                            try:
                                if _jimeng_auto_instance is not None:
                                    _jimeng_auto_instance.stop()
                            except:
                                pass
                            _jimeng_auto_instance = None
                            
                            if attempt == 0:
                                continue  # 重试
                            else:
                                raise Exception(f"浏览器重建后仍然失败: {error_msg}")
                        else:
                            raise  # 其他错误直接抛出
            
            loop = asyncio.get_event_loop()
            # ✅ 使用持久线程池
            submit_result = await loop.run_in_executor(_jimeng_thread_pool, _run_submit)
        
        print(f"   🔒 [{task_id}] 浏览器锁已释放（提交完成）")
        
        if not submit_result.get('success'):
            error_message = submit_result.get('error', '提交失败')
            task_manager.update_task(task_id, status=TaskStatus.FAILED, error=error_message)
            print(f"❌ 即梦任务提交失败: {task_id}\n错误: {error_message}")
            return
        
        history_id = submit_result.get('history_id', '')
        print(f"   ✅ [{task_id}] 提交成功，history_id={history_id}")
        
        # ============================================================
        # 阶段2：轮询结果（不需要浏览器锁，可并发）
        # ============================================================
        print(f"   ⏳ [{task_id}] 开始轮询结果（不占用浏览器锁）...")
        
        def _run_poll():
            global _jimeng_auto_instance
            auto = _jimeng_auto_instance
            if auto is None:
                raise Exception("即梦自动化实例丢失")
            
            result = auto.poll_result(
                history_id=history_id,
                max_wait=600,
                save_path=save_path,
            )
            return result
        
        loop = asyncio.get_event_loop()
        # ✅ 使用持久线程池
        result = await loop.run_in_executor(_jimeng_thread_pool, _run_poll)
        
        if result.get('success'):
            task_manager.update_task(
                task_id,
                status=TaskStatus.SUCCESS,
                result={
                    'success': True,
                    'local_video_path': save_path,
                    'video_url': result.get('video_url', ''),
                    'history_id': result.get('history_id', ''),
                    'message': '即梦视频生成成功',
                },
                message="即梦视频生成成功",
            )
            print(f"✅ 即梦任务成功: {task_id}")
        else:
            error_message = result.get('error', '未知错误')
            task_manager.update_task(
                task_id,
                status=TaskStatus.FAILED,
                error=error_message,
            )
            print(f"❌ 即梦任务失败: {task_id}\n错误: {error_message}")
    
    except asyncio.CancelledError:
        task_manager.update_task(task_id, status=TaskStatus.CANCELLED, error="任务被取消")
    except Exception as e:
        task_manager.update_task(task_id, status=TaskStatus.FAILED, error=f"执行异常: {str(e)}")
        print(f"❌ 即梦任务异常: {task_id}\n{e}")
    finally:
        task_manager.current_process = None


# ============================================================================
# Google Flow 自动化执行（图片生成）
# ============================================================================

_google_flow_auto_instance = None
_google_flow_auto_lock = None
_google_flow_thread_pool = concurrent.futures.ThreadPoolExecutor(max_workers=1, thread_name_prefix='google_flow_playwright')

def _get_google_flow_lock():
    """延迟创建 Google Flow 浏览器锁"""
    global _google_flow_auto_lock
    if _google_flow_auto_lock is None:
        _google_flow_auto_lock = asyncio.Lock()
    return _google_flow_auto_lock


async def execute_google_flow_automation(
    task_id: str,
    prompt: str,
    save_path: Optional[str] = None,
    tool_type: Optional[str] = 'text2image',
    model: Optional[str] = None,
    max_wait: int = 300,
    reference_file = None,
    aspect_ratio: Optional[str] = None,
    batch_count: Optional[int] = None,
):
    """
    后台异步执行 Google Flow 图片生成自动化
    
    两阶段架构：
    - 阶段1：提交生成（需要浏览器锁，保护 UI 操作）
    - 阶段2：轮询结果（无需锁，可并发等待）
    """
    try:
        task_manager.update_task(task_id, status=TaskStatus.RUNNING)
        
        print(f"\n{'='*60}")
        print(f"  🚀 开始执行 Google Flow 任务: {task_id}")
        print(f"  📝 提示词: {prompt}")
        if save_path:
            print(f"  📁 保存路径: {save_path}")
        print(f"{'='*60}\n")
        
        if save_path is None:
            downloads_dir = os.path.join(SCRIPT_DIR, 'downloads')
            os.makedirs(downloads_dir, exist_ok=True)
            save_path = os.path.join(downloads_dir, f'{task_id}.png')
        else:
            try:
                save_dir = os.path.dirname(save_path)
                if save_dir:
                    os.makedirs(save_dir, exist_ok=True)
            except OSError as path_err:
                print(f"  ⚠️  保存路径无效: {save_path}\n  错误: {path_err}")
                downloads_dir = os.path.join(SCRIPT_DIR, 'downloads')
                os.makedirs(downloads_dir, exist_ok=True)
                save_path = os.path.join(downloads_dir, f'{task_id}.png')
                print(f"  📁 已回退到默认路径: {save_path}")
        
        # ============================================================
        # 阶段1：提交生成（需要浏览器锁）
        # ============================================================
        lock = _get_google_flow_lock()
        print(f"   🔒 [{task_id}] 等待 Google Flow 浏览器锁...")
        
        async with lock:
            print(f"   🔓 [{task_id}] 获取到 Google Flow 浏览器锁")
            
            def _run_submit():
                from auto_google_flow import GoogleFlowAutomation
                
                global _google_flow_auto_instance
                
                for attempt in range(2):
                    try:
                        if _google_flow_auto_instance is None or not _google_flow_auto_instance._started:
                            _google_flow_auto_instance = GoogleFlowAutomation()
                            if not _google_flow_auto_instance.start():
                                raise Exception("无法启动 Google Flow 浏览器，请先登录")
                        
                        auto = _google_flow_auto_instance
                        
                        if not auto.check_login():
                            raise Exception("Google Flow 未登录，请先运行: python init_login.py google_flow")
                        
                        submit_result = auto.submit_generate(
                            prompt=prompt,
                            tool_type=tool_type or 'text2image',
                            model=model,
                            reference_file=reference_file,
                            aspect_ratio=aspect_ratio,
                            batch_count=int(batch_count) if batch_count else None,
                        )
                        
                        if not submit_result.get('success'):
                            err = submit_result.get('error', '')
                            browser_keywords = [
                                'browser has been closed',
                                'Target page, context or browser has been closed',
                                'cannot switch to a different thread',
                                'Connection refused', 'not connected',
                                'target closed', 'Session closed',
                            ]
                            if any(kw in err for kw in browser_keywords):
                                raise Exception(err)
                        
                        return submit_result
                        
                    except Exception as e:
                        error_msg = str(e)
                        if any(keyword in error_msg for keyword in [
                            'cannot switch to a different thread',
                            'browser has been closed',
                            'Target page, context or browser has been closed',
                            'Connection refused', 'not connected',
                            'target closed', 'Session closed',
                        ]):
                            print(f"   ⚠️  浏览器断开（尝试 {attempt + 1}/2）: {error_msg[:80]}")
                            print(f"   🔄 自动重建浏览器实例...")
                            try:
                                if _google_flow_auto_instance is not None:
                                    _google_flow_auto_instance.stop()
                            except:
                                pass
                            _google_flow_auto_instance = None
                            
                            if attempt == 0:
                                continue
                            else:
                                raise Exception(f"浏览器重建后仍然失败: {error_msg}")
                        else:
                            raise
            
            loop = asyncio.get_event_loop()
            submit_result = await loop.run_in_executor(_google_flow_thread_pool, _run_submit)
        
        print(f"   🔒 [{task_id}] Google Flow 浏览器锁已释放")
        
        if not submit_result.get('success'):
            error_message = submit_result.get('error', '提交失败')
            task_manager.update_task(task_id, status=TaskStatus.FAILED, error=error_message)
            print(f"❌ Google Flow 任务提交失败: {task_id}\n错误: {error_message}")
            return
        
        task_key = submit_result.get('task_key', '')
        generation_id = submit_result.get('generation_id', '')
        initial_images = submit_result.get('initial_images', [])
        has_reference = submit_result.get('has_reference', False)
        print(f"   ✅ [{task_id}] 提交成功，task_key={task_key}")
        
        # ============================================================
        # 阶段2：轮询结果（无需锁）
        # ============================================================
        effective_batch = int(batch_count) if batch_count and int(batch_count) > 1 else 1
        
        def _run_poll(poll_save_path, poll_initial_images):
            global _google_flow_auto_instance
            auto = _google_flow_auto_instance
            if auto is None:
                raise Exception("Google Flow 自动化实例丢失")
            
            result = auto.poll_result(
                task_key=task_key,
                initial_images=poll_initial_images,
                initial_image_count=len(poll_initial_images),
                max_wait=max_wait,
                save_path=poll_save_path,
                generation_id=generation_id,
                has_reference=has_reference,
            )
            return result
        
        loop = asyncio.get_event_loop()
        
        # 批量模式：多次 poll，每次收集一张新图并将其加入排除列表
        all_image_paths = []
        all_image_urls = []
        current_initial = list(initial_images)
        
        for batch_idx in range(effective_batch):
            # 为每张图生成不同的保存路径
            if effective_batch > 1 and save_path:
                base, ext = os.path.splitext(save_path)
                this_save_path = f"{base}_{batch_idx}{ext}"
            else:
                this_save_path = save_path
            
            result = await loop.run_in_executor(
                _google_flow_thread_pool,
                lambda sp=this_save_path, ci=list(current_initial): _run_poll(sp, ci),
            )
            
            if result.get('success'):
                img_url = result.get('image_url', '')
                img_path = result.get('image_path', this_save_path)
                all_image_urls.append(img_url)
                all_image_paths.append(img_path)
                # 把已找到的图片加入排除列表，下次 poll 不会重复检测
                if img_url:
                    current_initial.append(img_url)
                if batch_idx < effective_batch - 1:
                    print(f"   ✅ [{task_id}] 第 {batch_idx + 1}/{effective_batch} 张已获取")
            else:
                error_message = result.get('error', '未知错误')
                print(f"   ⚠️  [{task_id}] 第 {batch_idx + 1}/{effective_batch} 张失败: {error_message}")
                if batch_idx == 0:
                    # 第一张就失败，整个任务失败
                    task_manager.update_task(task_id, status=TaskStatus.FAILED, error=error_message)
                    print(f"❌ Google Flow 任务失败: {task_id}\n错误: {error_message}")
                    return
                break  # 后续的失败不影响已成功的
        
        if all_image_paths:
            task_manager.update_task(
                task_id,
                status=TaskStatus.SUCCESS,
                result={
                    'success': True,
                    'local_image_path': all_image_paths[0],
                    'image_url': all_image_urls[0] if all_image_urls else '',
                    'local_image_paths': all_image_paths,
                    'image_urls': all_image_urls,
                    'task_key': task_key,
                    'message': f'Google Flow 图片生成成功（{len(all_image_paths)}张）',
                },
                message=f"Google Flow 图片生成成功（{len(all_image_paths)}张）",
            )
            print(f"✅ Google Flow 任务成功: {task_id}（{len(all_image_paths)}张图片）")
        else:
            task_manager.update_task(
                task_id,
                status=TaskStatus.FAILED,
                error='未获取到任何图片',
            )
            print(f"❌ Google Flow 任务失败: {task_id}\n错误: 未获取到任何图片")
    
    except asyncio.CancelledError:
        task_manager.update_task(task_id, status=TaskStatus.CANCELLED, error="任务被取消")
        print(f"⚠️  Google Flow 任务取消: {task_id}")
    except Exception as e:
        error_message = f"执行异常: {str(e)}"
        task_manager.update_task(task_id, status=TaskStatus.FAILED, error=error_message)
        import traceback
        traceback.print_exc()
        print(f"❌ Google Flow 任务异常: {task_id}\n{error_message}")


# ============================================================================
# 浏览器窗口控制
# ============================================================================

def find_browser_window() -> Optional[Any]:
    """
    查找 Playwright 启动的浏览器窗口
    
    Returns:
        窗口对象，如果未找到则返回 None
    """
    if not WINDOW_CONTROL_AVAILABLE:
        return None
    
    try:
        # 查找包含特定关键词的窗口
        # Playwright 启动的 Chrome 窗口通常包含 "Chrome" 或网站标题
        all_windows = gw.getAllWindows()
        
        # 优先查找包含 "Vidu" 的窗口
        for window in all_windows:
            if window.title and ("vidu" in window.title.lower() or "chrome" in window.title.lower()):
                return window
        
        # 如果没找到，返回最近的 Chrome 窗口
        for window in all_windows:
            if window.title and "chrome" in window.title.lower():
                return window
        
        return None
        
    except Exception as e:
        print(f"⚠️  查找窗口失败: {e}")
        return None


def show_browser_window() -> BrowserControlResponse:
    """显示浏览器窗口（激活并置顶）"""
    if not WINDOW_CONTROL_AVAILABLE:
        return BrowserControlResponse(
            success=False,
            message="窗口控制功能不可用（pygetwindow 未安装）",
            window_found=False,
        )
    
    try:
        window = find_browser_window()
        
        if window is None:
            return BrowserControlResponse(
                success=False,
                message="未找到浏览器窗口",
                window_found=False,
            )
        
        # 恢复窗口（如果最小化）
        if window.isMinimized:
            window.restore()
        
        # 激活窗口（置顶）
        window.activate()
        
        return BrowserControlResponse(
            success=True,
            message=f"浏览器窗口已显示: {window.title}",
            window_found=True,
        )
        
    except Exception as e:
        return BrowserControlResponse(
            success=False,
            message=f"显示窗口失败: {str(e)}",
            window_found=False,
        )


def hide_browser_window() -> BrowserControlResponse:
    """隐藏浏览器窗口（最小化）"""
    if not WINDOW_CONTROL_AVAILABLE:
        return BrowserControlResponse(
            success=False,
            message="窗口控制功能不可用（pygetwindow 未安装）",
            window_found=False,
        )
    
    try:
        window = find_browser_window()
        
        if window is None:
            return BrowserControlResponse(
                success=False,
                message="未找到浏览器窗口",
                window_found=False,
            )
        
        # 最小化窗口
        window.minimize()
        
        return BrowserControlResponse(
            success=True,
            message=f"浏览器窗口已最小化: {window.title}",
            window_found=True,
        )
        
    except Exception as e:
        return BrowserControlResponse(
            success=False,
            message=f"最小化窗口失败: {str(e)}",
            window_found=False,
        )


# ============================================================================
# API 路由
# ============================================================================

@app.get("/")
async def root():
    """根路径：服务状态"""
    return {
        "service": "Vidu 自动化 API",
        "status": "running",
        "version": "1.0.0",
        "endpoints": {
            "generate": "POST /api/vidu/generate",
            "task_status": "GET /api/task/{task_id}",
            "all_tasks": "GET /api/tasks",
            "browser_show": "POST /api/browser/show",
            "browser_hide": "POST /api/browser/hide",
        }
    }


@app.get("/health")
async def health_check():
    """健康检查"""
    return {
        "status": "healthy",
        "timestamp": datetime.now().isoformat(),
        "window_control": WINDOW_CONTROL_AVAILABLE,
    }


@app.post("/api/vidu/generate", response_model=TaskResponse)
async def generate_video(request: GenerateRequest, background_tasks: BackgroundTasks):
    """
    核心接口 1：提交视频生成任务（Vidu 专用，保留兼容性）
    
    立即返回任务 ID，后台异步执行
    """
    # 生成任务 ID
    task_id = f"task_{datetime.now().strftime('%Y%m%d_%H%M%S_%f')}"
    
    # 创建任务
    task = task_manager.create_task(
        task_id=task_id,
        prompt=request.prompt,
        platform=request.platform,
    )
    
    # 添加后台任务（不阻塞接口）
    background_tasks.add_task(execute_vidu_automation, task_id, request.prompt, max_wait=900)
    
    print(f"\n✅ 任务已受理: {task_id}")
    print(f"📝 提示词: {request.prompt}\n")
    
    return TaskResponse(
        task_id=task_id,
        status=TaskStatus.PENDING,
        message="任务已受理，正在后台执行",
        created_at=task["created_at"],
        prompt=request.prompt,
    )


class UniversalGenerateRequest(BaseModel):
    """通用生成请求（支持多平台）"""
    platform: str  # vidu, jimeng, keling, hailuo
    tool_type: str  # text2video, img2video, text2image
    payload: Dict[str, Any]  # 包含 prompt, model 等参数


@app.post("/api/generate", response_model=TaskResponse)
async def generate_universal(request: UniversalGenerateRequest, background_tasks: BackgroundTasks):
    """
    通用生成接口（支持多平台、多工具类型）
    
    Args:
        platform: 平台名称（vidu, jimeng, keling, hailuo）
        tool_type: 工具类型（text2video, img2video, text2image）
        payload: 参数字典，包含 prompt, model, savePath 等
    
    立即返回任务 ID，后台异步执行
    """
    # 验证平台
    supported_platforms = ['vidu', 'jimeng', 'keling', 'hailuo', 'google_flow']
    if request.platform not in supported_platforms:
        raise HTTPException(
            status_code=400,
            detail=f"不支持的平台: {request.platform}，支持的平台: {', '.join(supported_platforms)}"
        )
    
    # 验证工具类型
    supported_tools = ['text2video', 'img2video', 'ref2video', 'text2image', 'video_gen', 'image_gen', 'agent']
    if request.tool_type not in supported_tools:
        raise HTTPException(
            status_code=400,
            detail=f"不支持的工具类型: {request.tool_type}，支持的工具: {', '.join(supported_tools)}"
        )
    
    # 验证必需参数
    if 'prompt' not in request.payload:
        raise HTTPException(status_code=400, detail="payload 必须包含 prompt 字段")
    
    # 生成任务 ID
    task_id = f"task_{datetime.now().strftime('%Y%m%d_%H%M%S_%f')}"
    
    # 创建任务
    task = task_manager.create_task(
        task_id=task_id,
        prompt=request.payload.get('prompt'),
        platform=request.platform,
        tool_type=request.tool_type,
        payload=request.payload,
    )
    
    # 根据平台选择执行函数
    if request.platform == 'vidu':
        # ✅ 从 payload 中提取保存路径和视频参数
        save_path = request.payload.get('savePath')
        aspect_ratio = request.payload.get('aspectRatio')
        resolution = request.payload.get('resolution')
        duration = request.payload.get('duration')
        tool_type = request.tool_type  # 从请求中获取工具类型
        model = request.payload.get('model')
        reference_file = request.payload.get('referenceFile')  # ✅ 获取参考文件路径
        character_name = request.payload.get('characterName')  # ✅ 获取主体库角色名称
        segments = request.payload.get('segments')  # ✅ 图片库模式：交替输入段落列表
        print(f"  🔍 [VIDU DEBUG] segments={segments}, tool_type={tool_type}", flush=True)
        
        # ✅ 从 payload 中提取超时配置（默认 900 秒 = 15 分钟）
        max_wait = int(request.payload.get('maxWait', 900))
        if max_wait < 60:
            max_wait = max_wait * 60  # 小于 60 视为分钟，转换为秒
        
        # ✅ 批量生成：batchCount > 1 时，一次填写提示词 + 点 N 次创作
        batch_count = int(request.payload.get('batchCount', 1))
        batch_count = max(1, min(batch_count, 10))  # 限制 1-10
        
        if batch_count > 1:
            # 批量模式：创建 N 个任务，一次 submit 点 N 次创作
            extra_task_ids = []
            for i in range(1, batch_count):
                extra_id = f"task_{datetime.now().strftime('%Y%m%d_%H%M%S_%f')}_{i}"
                task_manager.create_task(
                    task_id=extra_id,
                    prompt=request.payload.get('prompt'),
                    platform=request.platform,
                    tool_type=request.tool_type,
                    payload=request.payload,
                )
                extra_task_ids.append(extra_id)
            
            all_task_ids = [task_id] + extra_task_ids
            
            background_tasks.add_task(
                execute_vidu_batch_automation,
                all_task_ids,
                request.payload.get('prompt'),
                save_path,
                aspect_ratio, resolution, duration,
                tool_type, model, reference_file, character_name,
                max_wait, batch_count,
                segments,
            )
        else:
            # 单任务模式
            background_tasks.add_task(
                execute_vidu_automation, 
                task_id, 
                request.payload.get('prompt'),
                save_path,
                aspect_ratio,
                resolution,
                duration,
                tool_type,
                model,
                reference_file,
                character_name,
                max_wait,
                segments,
            )
    elif request.platform == 'jimeng':
        # ✅ 即梦：UI 自动化方案
        save_path = request.payload.get('savePath')
        aspect_ratio = request.payload.get('aspectRatio')
        resolution = request.payload.get('resolution')
        duration = request.payload.get('duration')
        tool_type = request.tool_type
        model = request.payload.get('model')
        mode = request.payload.get('mode')
        reference_file = request.payload.get('referenceFile')
        
        background_tasks.add_task(
            execute_jimeng_automation,
            task_id,
            request.payload.get('prompt'),
            save_path,
            aspect_ratio,
            resolution,
            duration,
            tool_type,
            model,
            mode,
            reference_file,
        )
    elif request.platform == 'google_flow':
        # ✅ Google Flow：图片生成自动化
        save_path = request.payload.get('savePath')
        model = request.payload.get('model')
        max_wait = int(request.payload.get('maxWait', 300))
        reference_file = request.payload.get('referenceFile')
        aspect_ratio = request.payload.get('aspectRatio')
        batch_count = request.payload.get('batchCount')
        
        background_tasks.add_task(
            execute_google_flow_automation,
            task_id,
            request.payload.get('prompt'),
            save_path,
            request.tool_type,
            model,
            max_wait,
            reference_file,
            aspect_ratio,
            batch_count,
        )
    else:
        # 其他平台暂未实现
        task_manager.update_task(
            task_id,
            status=TaskStatus.FAILED,
            error=f"平台 {request.platform} 功能开发中"
        )
    
    print(f"\n✅ 任务已受理: {task_id}")
    print(f"📝 平台: {request.platform}")
    print(f"📝 工具: {request.tool_type}")
    print(f"📝 提示词: {request.payload.get('prompt')}")
    if request.payload.get('savePath'):
        print(f"📁 保存路径: {request.payload.get('savePath')}")
    
    # 批量信息
    batch_count_val = int(request.payload.get('batchCount', 1)) if request.platform == 'vidu' else 1
    batch_count_val = max(1, min(batch_count_val, 10))
    batch_task_ids = None
    if batch_count_val > 1:
        # 收集本次批量创建的所有 task_id
        batch_task_ids = [task_id]
        for tid_key, t in task_manager.tasks.items():
            if tid_key != task_id and t.get('prompt') == request.payload.get('prompt') and t.get('status') == TaskStatus.PENDING:
                batch_task_ids.append(tid_key)
                if len(batch_task_ids) >= batch_count_val:
                    break
        print(f"📦 批量: {len(batch_task_ids)} 个任务 {batch_task_ids}")
    print()
    
    return TaskResponse(
        task_id=task_id,
        status=TaskStatus.PENDING,
        message="任务已受理，正在后台执行",
        created_at=task["created_at"],
        prompt=request.payload.get('prompt'),
        task_ids=batch_task_ids,
    )


@app.get("/api/task/{task_id}", response_model=TaskStatusResponse)
async def get_task_status(task_id: str):
    """
    查询任务状态
    
    Args:
        task_id: 任务 ID
    """
    task = task_manager.get_task(task_id)
    
    if task is None:
        # ✅ 添加详细的日志，帮助调试
        print(f"\n⚠️  查询不存在的任务: {task_id}")
        print(f"   当前存在的任务: {list(task_manager.tasks.keys())}")
        print(f"   任务总数: {len(task_manager.tasks)}\n")
        
        raise HTTPException(status_code=404, detail=f"任务不存在: {task_id}")
    
    return TaskStatusResponse(**task)


@app.get("/api/tasks")
async def get_all_tasks():
    """
    获取所有任务列表
    """
    tasks = task_manager.get_all_tasks()
    return {
        "total": len(tasks),
        "tasks": list(tasks.values()),
    }


@app.post("/api/browser/show", response_model=BrowserControlResponse)
async def show_browser():
    """
    核心接口 2：显示浏览器窗口
    
    激活并置顶浏览器窗口
    """
    result = show_browser_window()
    print(f"🖥️  显示浏览器: {result.message}")
    return result


@app.post("/api/browser/hide", response_model=BrowserControlResponse)
async def hide_browser():
    """
    核心接口 2：隐藏浏览器窗口
    
    最小化浏览器窗口
    """
    result = hide_browser_window()
    print(f"🖥️  隐藏浏览器: {result.message}")
    return result


@app.delete("/api/task/{task_id}")
async def cancel_task(task_id: str):
    """
    取消任务（如果正在运行）
    
    Args:
        task_id: 任务 ID
    """
    task = task_manager.get_task(task_id)
    
    if task is None:
        raise HTTPException(status_code=404, detail=f"任务不存在: {task_id}")
    
    if task["status"] == TaskStatus.RUNNING:
        # 尝试终止进程
        if task_manager.current_process:
            try:
                task_manager.current_process.terminate()
                task_manager.update_task(task_id, status=TaskStatus.CANCELLED)
                return {"message": f"任务已取消: {task_id}"}
            except Exception as e:
                raise HTTPException(status_code=500, detail=f"取消任务失败: {str(e)}")
        else:
            raise HTTPException(status_code=400, detail="无法找到运行中的进程")
    else:
        return {"message": f"任务状态为 {task['status']}，无需取消"}


# ============================================================================
# 启动服务
# ============================================================================

def print_startup_banner():
    """打印启动横幅"""
    banner = f"""
╔══════════════════════════════════════════════════════════╗
║                                                          ║
║          🚀 Vidu 自动化 API 服务器                        ║
║                                                          ║
║  本地地址: http://127.0.0.1:8123                         ║
║  API 文档: http://127.0.0.1:8123/docs                    ║
║                                                          ║
║  核心接口:                                                ║
║  • POST /api/vidu/generate    - 提交生成任务             ║
║  • GET  /api/task/{{task_id}}   - 查询任务状态            ║
║  • POST /api/browser/show     - 显示浏览器               ║
║  • POST /api/browser/hide     - 隐藏浏览器               ║
║                                                          ║
║  窗口控制: {'✅ 可用' if WINDOW_CONTROL_AVAILABLE else '❌ 不可用'}                                      ║
║                                                          ║
╚══════════════════════════════════════════════════════════╝
"""
    print(banner)


if __name__ == "__main__":
    # PyInstaller --onefile 需要 freeze_support 防止多进程重复启动
    import multiprocessing
    multiprocessing.freeze_support()
    
    print_startup_banner()
    
    # 启动 Uvicorn 服务器
    uvicorn.run(
        app,
        host="127.0.0.1",
        port=8123,
        log_level="info",
    )
