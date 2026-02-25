# -*- mode: python ; coding: utf-8 -*-
"""
PyInstaller 配置文件 - 打包 LaMa 水印去除引擎（极限瘦身版）
支持 Windows/Linux/Mac
"""
import sys

block_cipher = None

a = Analysis(
    ['main.py'],
    pathex=[],
    binaries=[],
    datas=[
        # 不打包模型文件，让它作为外部资源
    ],
    hiddenimports=[
        'uvicorn.logging',
        'uvicorn.loops',
        'uvicorn.loops.auto',
        'uvicorn.protocols',
        'uvicorn.protocols.http',
        'uvicorn.protocols.http.auto',
        'uvicorn.protocols.websockets',
        'uvicorn.protocols.websockets.auto',
        'uvicorn.lifespan',
        'uvicorn.lifespan.on',
        'onnxruntime',
        'onnxruntime.capi',
        'onnxruntime.capi.onnxruntime_pybind11_state',
    ],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[
        # 极限瘦身：排除所有不必要的庞然大物
        'torch',
        'torchvision',
        'torchaudio',
        'torch.distributed',
        'torch.nn',
        'torch.optim',
        'matplotlib',
        'matplotlib.pyplot',
        'scipy',
        'pandas',
        'PyQt5',
        'PyQt6',
        'PySide2',
        'PySide6',
        'tkinter',
        'IPython',
        'jupyter',
        'notebook',
        'sympy',
        'pytest',
        'setuptools',
        'wheel',
        'pip',
        # 排除不需要的 IPython 相关
        'jedi',
        'parso',
        'pygments',
        'prompt_toolkit',
        'traitlets',
        'ipykernel',
        # 排除测试框架
        'unittest',
        'doctest',
        # 排除其他大型库
        'PIL.ImageQt',
        'PIL.ImageTk',
        'xml.dom',
        'xml.sax',
        'pydoc',
        'pdb',
        'difflib',
        'inspect',
        'black',
        'yapf',
        'autopep8',
    ],
    win_no_prefer_redirects=False,
    win_private_assemblies=False,
    cipher=block_cipher,
    noarchive=False,
)

pyz = PYZ(a.pure, a.zipped_data, cipher=block_cipher)

# 根据平台设置不同的配置
if sys.platform == 'win32':
    # Windows: 隐藏控制台窗口
    exe = EXE(
        pyz,
        a.scripts,
        a.binaries,
        a.zipfiles,
        a.datas,
        [],
        name='watermark_engine',
        debug=False,
        bootloader_ignore_signals=False,
        strip=False,
        upx=True,  # 启用 UPX 压缩
        upx_exclude=[],
        runtime_tmpdir=None,
        console=True,  # 临时启用控制台以查看错误信息
        disable_windowed_traceback=False,
        argv_emulation=False,
        target_arch=None,
        codesign_identity=None,
        entitlements_file=None,
        icon=None,
    )
else:
    # Linux/Mac: 普通可执行文件
    exe = EXE(
        pyz,
        a.scripts,
        a.binaries,
        a.zipfiles,
        a.datas,
        [],
        name='watermark_engine',
        debug=False,
        bootloader_ignore_signals=False,
        strip=False,
        upx=True,
        upx_exclude=[],
        runtime_tmpdir=None,
        console=False,  # 后台运行
        disable_windowed_traceback=False,
        argv_emulation=False,
        target_arch=None,
        codesign_identity=None,
        entitlements_file=None,
    )
