#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
最简单的 Flutter-Python 通信测试脚本
用于验证命令行参数传递和 JSON 输出
"""

import sys
import json
import io

# 确保标准输出使用 UTF-8 编码（Windows 兼容）
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')


def main():
    """主函数：接收参数并返回 JSON 结果"""
    
    # 获取命令行参数
    if len(sys.argv) > 1:
        user_input = sys.argv[1]
    else:
        user_input = "未提供参数"
    
    # 构建返回结果
    result = {
        "success": True,
        "message": "Hello from Python! 你好，Flutter！",
        "received_param": user_input,
        "test_chinese": "中文测试：星河AI创作工具",
        "emoji_test": "🎨✨🚀",
    }
    
    # 输出 JSON（ensure_ascii=False 确保中文正常显示）
    output = json.dumps(result, ensure_ascii=False, indent=2)
    print(output)
    
    return 0


if __name__ == "__main__":
    try:
        exit_code = main()
        sys.exit(exit_code)
    except Exception as e:
        # 错误也以 JSON 格式返回
        error_result = {
            "success": False,
            "error": str(e),
            "message": "脚本执行失败"
        }
        print(json.dumps(error_result, ensure_ascii=False, indent=2))
        sys.exit(1)
