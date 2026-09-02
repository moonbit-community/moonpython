# CPython 行为对齐 TODO

范围：`main..fix-tests`。下列 hash 均为当前分支中的提交。
对齐基线为 CPython 3.13；`reference_test` 中仍混有 Python 3.14 注解测试，需先统一版本。

## 完成标准

- 参考解释器与测试源码固定到同一 CPython tag，参考程序不继承生成器的 future flags。
- 默认语言语义与受限 sandbox 配置分开测试。
- 每项修复包含 CPython/MoonPython 差分测试和反例。
- `moon check --target native`、`moon test --target native` 通过。
- 执行 `moon info && moon fmt`，确认 `.mbti` 变化符合预期。

## P0：修复测试预言机

### [ ] P0-1 隔离生成器的 future flags

位置：`scripts/generate_spec_tests.py` 的 `eval_expression`、`eval_program`。

生成器自身启用了 `from __future__ import annotations`，直接 `eval`/`exec` 字符串会让
参考程序继承该 flag。改为先用 `compile(..., flags=0, dont_inherit=True)` 编译，再执行
code object；片段自身的 future import 仍正常生效。

验收：默认注解和显式 future 注解有独立自测，重新生成并核对 annotation/type-alias 预期。

### [ ] P0-2 固定 CPython 版本和测试来源

位置：`scripts/generate_spec_tests.py`、`reference_test`、`Lib/test`、CI。

生成命令仍写 Python 3.12，`REFERENCE_VERSION` 声明 3.13，版本检查又允许 3.12/3.13；
部分注解测试使用 3.14 的 `annotationlib` / `__annotate__`。

验收：统一为 CPython 3.13.x，记录测试源码 tag/commit，隔离 3.14 语料；解释器版本不符时
生成器和 CI 明确失败。

### [ ] P0-3 分离默认 CPython 语义与 spec sandbox

相关提交：`44ce3f0`、`cbb8a67`、`a641369`、`dbb9b90`、`4aa5db0`、`6b5d0fd`。
位置：生成器的 `SAFE_BUILTINS`、`safe_import`、`format_error`，以及运行时配置。

当前参考环境删除了 `type`、`super`、`BlockingIOError` 等 builtin，限制 import，并自定义
异常展示。这些配置不能作为默认 CPython 的语言语义基准。

验收：使用完整 builtins 生成默认语义结果；allowlist、缺失 builtin、math shim 单独测试。
异常类型、`str(exc)`、行列位置保存为结构化结果，API 格式化与 CLI traceback 分别验证。

## P1：补全现有实现

### [ ] P1-1 补全 PEP 695 类型参数与 TypeAliasType

相关提交：`bdf31d2`、`6c4e71b`。
位置：`bytecode_compiler.mbt`、`runtime_object_attr.mbt`。

- 泛型函数、类和 alias 暴露 `__type_params__`，type parameter 在对应 annotation scope 中可见。
- alias 的 `__value__` 求值失败可重试，第一次成功后缓存，名称删除后仍能读取缓存。
- 对齐 `__name__`、`__module__`、参数化和 repr；参考 `Lib/test/test_type_aliases.py`。

### [ ] P1-2 统一 keyword / identifier 校验

相关提交：`b68393c`、`e979e17`、`bb14618`。
位置：`parser_line_defs.mbt`、`parser_line_helpers.mbt`、`parser_line.mbt`。

函数名、类名、参数、import/except alias、pattern capture 复用统一校验，拒绝所有 hard
keywords，并按目标版本处理 soft keywords。覆盖 `def for():`、`class return:` 等反例。

### [ ] P1-3 统一静态 block 深度限制

相关提交：`48a4590`。位置：`parser_line.mbt`。

当前只限制 `while` 嵌套。改为在统一 block-stack 入口计数，覆盖 `for`、`with`、`try`、
`finally` 及混合嵌套，并与固定版本 CPython 做差分测试。

### [ ] P1-4 补全 star import 的 module-only 规则

相关提交：`5338084`。位置：`parser_line_defs.mbt`、`parser_stmt.mbt`。

在 AST scope validation 阶段统一判断作用域，分别验证 module、function、nested function
和 class body 中的 star import。

### [ ] P1-5 恢复 sorted 比较失败的错误信息

相关提交：`93fc2d4`。位置：`runtime_builtins_core.mbt`。

当前错误统一为 `sorted() cannot compare values`。由通用 rich comparison 路径保留实际
运算符和左右类型，例如 `'<' not supported between instances of 'str' and 'int'`。

### [ ] P1-6 移除 class comprehension 的硬编码 SystemError

相关提交：`b5af4aa`。位置：`bytecode_vm.mbt`、`runtime_block.mbt`、`parser_stmt.mbt`。

实现 `__classcell__`、class closure 和 comprehension scope，让名称解析及错误由通用路径
产生，移除按全局 `__class__` 和源码形态拼接固定 SystemError 的分支。

## P2：诊断维护

### [ ] P2-1 使用 token / AST span 定位错误

相关提交：`12116b7`、`f0b7776`、`082f514`、`30ad346`。
位置：lexer、parser 及错误格式化路径。

token 保存起止 span，parser error 携带失败 token，格式化层不再扫描源码猜测行号。
覆盖字符串、注释、嵌套函数和多行表达式中的关键字，避免文本启发式误判。

## 当前提交索引

✅：覆盖用例的窄行为对齐；⚠️：部分实现或受限环境行为，仍有上述待办；—：无 Python 语义变化。

| Commit | 判定 | 说明 / TODO |
|---|:---:|---|
| `017c9ce` | ✅ | parenthesized `del` target 对齐 |
| `bc7030b` | ✅ | f-string repr 快照对齐 |
| `cfaff6d` | ✅ | 覆盖用例的 traceback column 对齐 |
| `8902c3e` | ✅ | dict constructor 输出对齐 |
| `6c3f1e0` | ✅ | `dict.pop` 输出对齐 |
| `68a687c` | ✅ | `dict.setdefault` 输出对齐 |
| `e44c3b9` | ✅ | dict view list snapshot 对齐 |
| `7e7b5a3` | ✅ | `dict.update` 输出对齐 |
| `1c5a6d8` | ✅ | numeric dict key 去重对齐 |
| `0d302fb` | ✅ | `except*` group splitting 对齐 |
| `eefef5d` | ✅ | `except*` remainder reraising 对齐 |
| `d5d32d5` | ✅ | async for-else 顺序对齐 |
| `93fc2d4` | ⚠️ | 见 P1-5 |
| `789fb58` | ✅ | zip iterator 消耗行为对齐 |
| `57c1d95` | ✅ | span 内非法 await 检查方向正确 |
| `b33fcc4` | ✅ | 覆盖 builtin fixture 对齐 |
| `f6577ea` | ✅ | `Exception` 捕获 builtin error 的层级对齐 |
| `df80c88` | ✅ | comprehension 第一个 iterable 外层求值对齐 |
| `9cacea8` | ✅ | span 内 yield 检查对齐 |
| `b69377c` | ✅ | assignment RHS 先于 target |
| `44ce3f0` | ⚠️ | 见 P0-3 |
| `cbb8a67` | ⚠️ | 见 P0-3 |
| `a641369` | ⚠️ | 见 P0-3 |
| `e0adb44` | ✅ | bound `int.__hash__` 对齐 |
| `bdf31d2` | ⚠️ | 见 P1-1 |
| `231109a` | ✅ | 首个非法 await 行号对齐 |
| `956208f` | ✅ | nested f-string brace balance 对齐 |
| `6c4e71b` | ⚠️ | 见 P1-1 |
| `45cc78c` | ✅ | 覆盖的 valueless annotation 非法形式正确 |
| `6181c90` | ✅ | 跨 span 的 docstring 读取对齐 |
| `b15662a` | ✅ | 拒绝 bare async assignment |
| `98b1281` | ✅ | 拒绝 consecutive await |
| `0e5a0a2` | ✅ | 拒绝参数默认值中的 await |
| `84e95d4` | ✅ | 直接参数注解中的 await 检查方向正确 |
| `b68393c` | ✅ | 拒绝 async/await 作为定义名；完整校验见 P1-2 |
| `082f514` | ✅ | 覆盖用例的 await diagnostic 对齐 |
| `dbfe875` | ✅ | 拒绝 annotated unpacking target |
| `1f79c6c` | ✅ | 拒绝非法 brace comprehension target |
| `290d0cc` | ✅ | `except*` 非法控制流静态检查对齐 |
| `e979e17` | ⚠️ | 见 P1-2 |
| `bb14618` | ⚠️ | 见 P1-2 |
| `dbb9b90` | ⚠️ | 见 P0-3 |
| `b5af4aa` | ⚠️ | 见 P1-6 |
| `5338084` | ⚠️ | 见 P1-4 |
| `12116b7` | ⚠️ | 见 P2-1 |
| `f0b7776` | ✅ | regex fragment first-line diagnostic 对齐 |
| `0b389a9` | ✅ | nonlocal 与参数名冲突检查对齐 |
| `48a4590` | ⚠️ | 见 P1-3 |
| `a52a39d` | ✅ | 覆盖的 control-flow position 对齐 |
| `428efba` | ✅ | 拒绝 backslash 后 comment continuation |
| `30ad346` | ✅ | 覆盖的 call missing-comma 行号对齐 |
| `6788149` | ✅ | 保留片段自身的 `__future__` import 执行 |
| `4aa5db0` | ⚠️ | 见 P0-3 |
| `6b5d0fd` | ⚠️ | 见 P0-3 |
| `0aa4c8a` | — | moon info/fmt 产物维护 |
| `98fcce7` | — | MoonBit warning 清理 |
| `366b179` | — | MoonBit promote/manifest 迁移 |
| `0a5dc30` | — | warning/构造语法维护 |

其他维护提交包括 MoonBit 格式和整数类型名称更新、显式公开 ToJson 方法、测试 API 引用与
JSON import 修复。

## 验证记录

最近一次代码验证结果（本次仅整理文档，未重新生成测试或更新 snapshot）：

- `moon check --target native`：通过。
- `moon test --target native`：2940 个测试中，2868 通过、72 失败；失败全部位于
  `spec_generated_test.mbt`，其他测试均通过。
- `moon info && moon fmt`：通过，`.mbti` 无变化。
- native CLI 的 17 个定向检查通过，使用 `--stdlib Lib`；不替代固定版本 CPython 差分测试。

失败编号均为 `generated/program/NNNN`：

| 行为 | 编号 | 数量 |
|---|---|---:|
| 注解求值、语法和求值顺序 | 0125–0126、0147–0148、0256、0476、0575、0947–0949 | 10 |
| async comprehension / generator | 0151–0156、0400 | 7 |
| `code.co_positions()` | 0340 | 1 |
| global 静态校验和诊断 | 0571–0574、0830 | 5 |
| 多行缺逗号诊断 | 0630 | 1 |
| class nonlocal / private walrus | 0669、0689–0690 | 3 |
| pattern grammar 与静态校验 | 0700–0742、0880 | 44 |
| 空 `Exception` 的展示 | 0983 | 1 |

失败包含参考预期问题和实现缺口，先完成 P0，再逐组验证。
