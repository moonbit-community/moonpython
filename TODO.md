# CPython 行为对齐 TODO

> 审查范围：`main..fix-tests`，共 74 个提交，审查时 HEAD 为 `b65123b`。
>
> 对齐基线：仓库生成器声明的 CPython 3.13。当前 `reference_test` 中混有
> Python 3.14 注解测试，因此在解决版本混用前，不能把现有生成测试视为单一版本的
> CPython 行为基准。
>
> 审查结果：40 个窄行为对齐，16 个部分对齐或只对齐受限测试环境，14 个存在明确
> CPython 反例，4 个是无 Python 语义变化的维护提交。

## 完成标准

只有同时满足以下条件，才应勾选“CPython 行为已对齐”：

- 参考结果由明确固定的小版本 CPython 生成，测试源码也来自同一 CPython tag。
- 参考程序没有意外继承生成器自身的 `__future__` compiler flags。
- 默认 CPython 语义测试与 MoonPython 的受限 spec/sandbox 测试分开维护。
- 每个修复都有至少一个 CPython/MoonPython 差分测试，且包含曾经失败的反例。
- `moon check --target native` 和 `moon test --target native` 均通过。
- 最后执行 `moon info && moon fmt`，并确认 `.mbti` 变化符合预期。

## P0：先修复测试预言机

### [ ] P0-1 隔离生成器的 `from __future__ import annotations`

相关位置：

- `scripts/generate_spec_tests.py:9`
- `scripts/generate_spec_tests.py:206`
- `scripts/generate_spec_tests.py:220`

详细原因：

- 生成器模块自身声明了 `from __future__ import annotations`。
- `eval_expression` 和 `eval_program` 直接把字符串传给 `eval`/`exec`。
- 字符串在这种调用方式下会继承调用者的 future compiler flags，所以所有参考片段都在
  “postponed annotations” 模式中编译，即使片段自身没有 future import。
- 这使 CPython 3.13 默认的立即注解求值被静默改成 postponed annotations，直接导致
  `58e0f56`、`1916e69`、`ad9818a` 等提交依据错误预期删除注解行为。

最小反例：

```python
# CPython 3.13 默认模式：定义函数时应抛出 NameError。
def f(x: missing):
    pass
```

```python
# 只有片段显式声明 future import 时，定义才不应求值 missing。
from __future__ import annotations

def f(x: missing):
    pass
```

建议修复：

- 保留生成器自身的 future import 也可以，但不要再直接执行字符串。
- 对表达式使用
  `compile(source, filename, "eval", flags=0, dont_inherit=True)`，再执行生成的 code object。
- 对程序使用
  `compile(source, filename, "exec", flags=0, dont_inherit=True)`，再执行生成的 code object。
- 片段源码自身包含 future import 时，仍应由该片段正常启用相应语义。
- 更稳妥的长期方案是由固定版本的 CPython 子进程执行每个参考程序，从进程级隔离生成器
  的 globals、builtins、warnings 和 compiler flags。

验收条件：

- 增加生成器自测，证明默认注解和显式 future 注解产生不同结果。
- 重新生成测试后，检查所有 annotation/type-alias 相关 snapshot 的变化。

### [ ] P0-2 固定唯一 CPython 版本和唯一测试语料来源

相关位置：

- `scripts/generate_spec_tests.py:5` 要求使用 `python3.12` 重新生成。
- `scripts/generate_spec_tests.py:33` 声明 `REFERENCE_VERSION = "3.13"`。
- `scripts/generate_spec_tests.py:115` 又允许 Python 3.12 或 3.13、拒绝 3.14。
- `reference_test/test_type_annotations.py:1` 导入 `annotationlib`，并测试
  `__annotate__`，这是 Python 3.14 的延迟注解模型。
- `Lib/` 中的其他测试主要来自 CPython 3.13。

详细原因：

- Python 3.13 默认立即求值函数注解；Python 3.14 默认采用 PEP 649 延迟注解。
- 把两个版本的测试混合起来后，同一份实现不可能同时满足两套互相冲突的默认语义。
- 只在 URL 中写 `3.13` 不够；生成参考结果的解释器版本和复制的 CPython 测试 tag 也必须
  一致。

建议修复：

- 当前建议明确固定为 CPython 3.13.x。
- 生成器启动时检查 `sys.version_info[:2] == (3, 13)`，版本不符就失败。
- 在仓库中记录 CPython tag/commit hash，以及 `Lib/test` 文件的同步来源。
- 移除或单独隔离 Python 3.14 的 `annotationlib`/`__annotate__` 测试。
- 如果项目决定升级到 3.14，应作为独立迁移任务，重新设计全部注解运行时，而不是仅更新
  snapshot。

验收条件：

- 生成器、文档、CI Python 版本和 vendored tests 均指向同一 CPython 小版本。
- CI 在错误 Python 版本下生成测试时明确失败。

### [ ] P0-3 分离“默认 CPython 语义”和“受限 spec sandbox 行为”

影响提交：

- `921ebd0`：disabled import 的优先级。
- `a6fae78`：从 spec builtins 删除 `BlockingIOError`。
- `4ae0f6d`：从 spec builtins 删除 `type`。
- `b396fc5`：从 spec builtins 隐藏 `super`。
- `7801346`：relative import 走 allowlist。
- `0c7f73c`：默认允许 `math` shim。

相关位置：

- `scripts/generate_spec_tests.py:143` 的 `safe_import`。
- `scripts/generate_spec_tests.py:149` 的 `SAFE_BUILTINS`。
- `scripts/generate_spec_tests.py:231` 的 `format_error`。

详细原因：

- 默认 CPython 包含 `type`、`super`、`BlockingIOError` 等 builtin。
- 当前生成器主动删除它们，并只允许 `math`、`functools`、`itertools` 三个 import。
- 因而若 MoonPython 为了通过生成测试也删除 builtin，它只是在模仿测试 sandbox，不是在模仿
  CPython。
- `format_error` 把所有普通异常格式化成 `ClassName: message`。例如空
  `Exception()` 被格式化成 `Exception: `，而 CPython CLI traceback 的末行是
  `Exception`，这造成 `9a461a0` 和 `e21f1c6` 的错误修复。

建议修复：

- 使用完整 CPython builtins 生成“语言语义”参考结果。
- 将 import allowlist、缺失 builtin、math shim 放到独立的 `spec_sandbox_test` 中。
- 参考结果使用结构化字段保存异常类型、`str(exc)`、语法错误行列；不要把自定义展示字符串
  当成 CPython 本身的错误输出。
- 如果还需要验证 CLI traceback，应单独捕获 CPython 子进程的真实 stderr。

验收条件：

- `type`、`super`、`BlockingIOError` 在默认兼容模式下与 CPython 可见性一致。
- sandbox 测试明确标注为 MoonPython 配置行为，不再命名为 CPython parity。
- 空异常消息同时覆盖结构化异常值和真实 CLI traceback 两类测试。

## P0：恢复注解语义

### [ ] P0-4 实现 CPython 3.13 默认注解与 future annotations 两条路径

影响提交：

- `58e0f56`：避免 eager annotation evaluation。
- `1916e69`：忽略变量注解。
- `ad9818a`：忽略参数和返回注解。
- `aab7cdd`、`6e307b1`、`3bfd301`：相关的注解语法校验。

相关实现：

- `bytecode_compiler.mbt:1852`：`AnnAssign` 直接丢弃 annotation。
- `bytecode_compiler.mbt:2538`：函数 annotations 和 return annotation 被丢弃。
- `runtime_block.mbt:1513`、`runtime_block.mbt:1833`：解释执行路径同样丢弃注解。
- `parser_line_defs.mbt:770`、`parser_line_defs.mbt:874`：解析失败被替换为
  `Literal::None`。
- `parser_stmt.mbt:4011`：赋值注解解析失败也可能被替换为 `None`。

详细原因：

- CPython 3.13 默认在函数定义执行时求值参数和返回注解，并保存到
  `function.__annotations__`。
- module/class scope 的简单名称 annotated assignment 会维护 `__annotations__`。
- `from __future__ import annotations` 下也不是“删除注解”，而是保存字符串化的延迟形式。
- 当前实现既不求值、也不保存；不存在的名称不会抛错，合法注解元数据也消失。
- 更严重的是，语法分析错误被替换为 `None`，使非法 Python 可能继续执行。
- function local variable annotations 与 module/class annotations 的规则不同，不能用一个
  “全部求值”或“全部忽略”的分支处理。

必须加入的差分测试：

```python
x: int = 1
assert __annotations__ == {"x": int}
```

```python
def f(x: int) -> str:
    pass

assert f.__annotations__ == {"x": int, "return": str}
```

```python
# 默认 CPython 3.13：定义时 NameError。
def f(x: missing):
    pass
```

```python
from __future__ import annotations

def f(x: missing) -> list[missing]:
    pass

assert f.__annotations__ == {"x": "missing", "return": "list[missing]"}
```

还应覆盖：

- class scope 的 `__annotations__`。
- 只有 annotation、没有 value 的 annotated assignment。
- function local variable annotation 不应错误地在运行时求值。
- 默认参数、decorator、annotation 的 CPython 求值顺序。
- 参数注解、返回注解、变量注解中的非法语法始终抛 `SyntaxError`。

验收条件：

- 删除所有“解析失败就替换成 `None`”的恢复路径，除非调用者明确处于 error recovery 模式。
- bytecode 和 fallback interpreter 两条执行路径产生相同注解行为。
- 默认模式和 future 模式都有独立差分测试。

## P1：运行时对象行为

### [ ] P1-1 补全 `TypeAliasType` 的惰性缓存和元数据

影响提交：`1342668`，并关联 `9cfd969` 的泛型类/type parameter 支持。

相关实现：`runtime_object_attr.mbt:384`。

详细原因：

- 当前每次读取 `TypeAlias.__value__` 都重新调用 `__value_func__`。
- CPython 第一次成功求值后会缓存结果；之后即使原名称被删除，缓存仍然有效。
- 当前对象还缺少或没有正确维护 `__type_params__`、`__module__` 等属性。
- 这意味着当前提交只实现了“延迟”，没有实现 CPython 的 TypeAliasType 对象协议。

必须加入的差分测试：

```python
x = 1
type A = x
assert A.__value__ == 1
x = 2
assert A.__value__ == 1
```

```python
type Missing = value
try:
    Missing.__value__
except NameError:
    pass
value = int
assert Missing.__value__ is int
del value
assert Missing.__value__ is int  # 成功结果必须已缓存
```

参考：`Lib/test/test_type_aliases.py:172` 至 `Lib/test/test_type_aliases.py:205`。

验收条件：

- 失败求值可以在环境变化后重试，第一次成功求值后必须缓存。
- `__name__`、`__value__`、`__type_params__`、`__module__` 与 CPython 对齐。
- 泛型 alias 的参数化和 repr 有差分测试。

### [ ] P1-2 实现真正逐指令的 `code.co_positions()`

影响提交：`562ca0e`。

相关实现：`runtime_object_factories.mbt:303`。

详细原因：

- 当前所有 code object 都只保存一个
  `(co_firstlineno, co_firstlineno, 0, 0)`。
- CPython 的 `co_positions()` 为每条 bytecode instruction 提供
  `(start_line, end_line, start_column, end_column)`。
- 固定单元素列表只能满足“属性存在”的浅层测试，无法支持 traceback 精确列位置、调试器和
  coverage 工具。

建议修复：

- 在 bytecode emitter 中为每条指令保留 source span。
- 生成 code object 时将 span 表转换成与指令数对应的位置序列。
- 对人工生成、无位置信息的指令按 CPython 规则返回 `None` 字段，而不是伪造零列。

验收条件：

- `len(list(code.co_positions()))` 与可比较的 bytecode instruction 数量一致。
- 多行表达式、comprehension、异常处理和无位置信息指令都有测试。

## P1：作用域感知的静态检查

### [ ] P1-3 修复 `global` 名称使用检查跨越嵌套作用域

影响提交：`f5636c0`。

相关实现：`parser_stmt.mbt:1132` 的 `collect_expr_names_for_global_check`。

详细原因：

- 扫描器递归进入 lambda body、comprehension element、filters 和所有 iterable。
- lambda body 和 comprehension 的大部分表达式属于新的隐式作用域，不应算作当前函数在
  `global` 之前使用名称。
- comprehension 的第一个 iterable 又确实在外层作用域求值，所以也不能简单地完全跳过
  comprehension。

合法但当前会被拒绝：

```python
def f():
    [x for x in ()]
    global x
```

```python
def f():
    lambda: x
    global x
```

仍然应被拒绝：

```python
def f():
    [y for y in x]  # 第一个 iterable x 在 f 的作用域中求值
    global x
```

建议修复：

- 用显式 scope/symbol-table pass 代替“遍历整棵表达式收集名称”。
- 为 lambda、function、class、comprehension 建立 scope boundary。
- 单独建模 comprehension 第一个 iterable 的外层求值规则。

### [ ] P1-4 修复 class body 中的 `nonlocal` 与 comprehension walrus 校验

影响提交：`5c9b4c1`。

相关实现：

- `parser_stmt.mbt:1610` 无条件把 class body 中的 `Nonlocal` 判为非法。
- `parser_expr.mbt:1503` 对所有以双下划线开头的名称进行特殊豁免。

详细原因：

- 嵌套在函数中的 class body 可以用 `nonlocal` 引用外层函数绑定。
- 双下划线 name mangling 只应在适当的 class 编译上下文中应用，不能成为普通函数
  comprehension walrus 冲突检查的全局豁免。

合法反例：

```python
def f():
    x = 1
    class C:
        nonlocal x
        x = 2
    return x

assert f() == 2
```

非法但当前可能被接受：

```python
def f():
    return [(__x := 2) for __x in range(2)]
```

建议修复：

- 在符号表阶段解析 `nonlocal` 的 enclosing function binding。
- 将 class name-mangling context 显式传入，而不是按名称字符串全局猜测。

### [ ] P1-5 注解中的 yield/walrus 检查必须尊重 future 模式和嵌套作用域

影响提交：`3bfd301`。

相关实现：

- `parser_stmt.mbt:228` 的 `expr_has_yield_or_await` 进入 lambda body。
- `parser_stmt.mbt:317` 的 `expr_has_named_expr` 也递归进入 lambda body。
- `parser_stmt.mbt:324` 无条件组合成 `expr_is_invalid_annotation_value`。

详细原因：

- 在 CPython 3.13 默认模式中，named expression 可以作为普通立即求值注解的一部分。
- postponed/annotation scope 中对 named expression、yield、await 的限制不同，必须由当前
  compiler future flags 决定。
- 即使当前 annotation scope 禁止某个表达式，嵌套 lambda/function scope 内仍可能合法。

必须覆盖：

```python
# 默认 3.13 模式应按默认注解规则处理，而不是无条件拒绝。
def f(x: (y := 1)):
    pass
```

```python
from __future__ import annotations

# 禁令不能穿过 lambda 作用域。
def f(x: (lambda: (y := 1))):
    pass
```

建议修复：

- validator 接收明确的 annotation mode 和 scope depth。
- 遇到 lambda/function/comprehension 的新作用域时按 CPython execution model 停止或切换
  校验上下文。

## P1：语法和求值语义回归

### [ ] P1-6 允许同步函数中的 async generator expression

影响提交：`e1034d3`、`8663752`。

相关实现：`parser_line_defs.mbt:1147` 附近的函数体文本扫描。

详细原因：

- CPython 从 3.7 起允许 asynchronous generator expression 出现在任意函数中。
- 同步函数中的 async list/set/dict comprehension 仍然非法。
- 当前实现只查找文本中的 `async for`，没有区分 generator expression 与 materializing
  comprehension。

合法反例：

```python
def f():
    return (x async for x in agen())
```

建议修复：解析完成后根据 AST 节点种类和所在函数作用域校验，不要扫描源码文本。

### [ ] P1-7 用完整 pattern grammar 替代 match token 黑名单

影响提交：`8e95055`。

相关实现：`parser_line_match.mbt:189` 的 `match_pattern_has_invalid_syntax`。

详细原因：

- 当前只要 pattern 文本含 `|`、`+`、`*`、` as `、`=` 就直接判为非法。
- 其中 `|` 是 OR pattern，`as` 是 AS pattern，`*` 是 starred sequence pattern，`=` 用于
  class keyword pattern，都是官方语法组成部分。
- 字符串 token 黑名单也无法正确处理这些字符出现在字符串字面量或嵌套结构中的情况。

必须加入的合法测试：

```python
match value:
    case 1 | 2:
        pass
    case [first, *rest]:
        pass
    case Point(x=0, y=y) as point:
        pass
```

建议修复：为 OR、AS、star、mapping、class、sequence pattern 建立真实 parser 节点，再在 AST
上检查 duplicate captures、irrefutable ordering 等规则。

### [ ] P1-8 不要把相邻字符串字面量误判为多行 list 缺逗号

影响提交：`78631cd`。

相关实现：`parser_stmt.mbt:2883`。

详细原因：

- 当前逻辑按换行切分文本，只检查前两个元素文本是否含逗号。
- Python 允许相邻字符串字面量在编译期隐式拼接，因此下面代码等价于 `['ab']`：

```python
[
    "a"
    "b"
]
```

- 同一启发式还可能被注释、括号、三引号字符串和嵌套表达式干扰。

建议修复：由 token/parser 判断一个表达式是否已经结束；不要在 simple statement 层按行猜测
逗号是否缺失。

### [ ] P1-9 保留 parenthesized comprehension target 的真实赋值目标

影响提交：`b5a6ca7`。

相关实现：`parser_expr.mbt:1257`。

详细原因：

- 当括号 target 后还有 attribute/subscript suffix 时，当前 parser 跳到 `in` 并返回
  `Target::Name("_")`。
- 代码因此可能成功解析，但实际赋值目标完全丢失，比直接报告“不支持”更危险。

反例：

```python
class Box:
    pass

b = Box()
result = [b.x for (b).x in [1]]
assert result == [1]
assert b.x == 1
```

建议修复：让 target parser 正常构造 parenthesized primary 后的 Attribute/Subscript target；无法
支持时应明确抛语法或 NotImplemented 错误，绝不能替换成 `_`。

### [ ] P1-10 统一使用完整 keyword/identifier 校验

影响提交：`141426a`、`e25e332`、`13df95e`。

相关实现：

- `parser_line_defs.mbt:436` 只排除 `None`、`True`、`False`。
- `parser_line_helpers.mbt:338` 只单独处理 `async`、`await`。
- `parser_line.mbt:2039` 的 except alias 只检查字母数字和下划线。

详细原因：

- Python 所有保留关键字都不能作为函数名、类名、参数名或 except alias。
- 当前分散的检查表不一致，使 MoonPython 接受 `def for():`、`def f(for):`、
  `class return:`、`except Exception as for:` 等代码。

建议修复：

- 建立唯一的 `is_valid_identifier`/`is_keyword` 实现，由 lexer 提供 token kind。
- function/class 名、参数、import alias、except alias、capture pattern 等位置复用同一校验。
- 覆盖所有 hard keywords，并按目标版本单独处理 soft keywords。

### [ ] P1-11 对所有静态 block 类型统一执行 CPython 深度限制

影响提交：`1d25f31`。

相关实现：`parser_line.mbt:1531` 只在 `while` 分支检查 `block_depth >= 20`。

详细原因：

- CPython 的 compiler block stack 不只包含 `while`，还包括 `for`、`with`、`try` 等结构。
- 当前 21 层 `while` 会被拒绝，但 21 层 `for`、`with` 或混合结构仍可通过 parser。
- 这说明限制加在了某一个语句分支，而不是 compiler block push 的统一入口。

建议修复：在统一的 block-stack API 中计数，并为 while/for/with/try/finally 及混合嵌套生成
差分测试。

### [ ] P1-12 完整实现 star import 的 module-only 作用域规则

影响提交：`933b32e`。

详细原因：

- 提交覆盖了函数内 star import 的主要用例，但规则本质是“只能在 module level”。
- 校验需要明确处理 function、lambda、class 和其他嵌套 scope，而不是只查函数文本。

建议修复：在 import AST 的 scope validation 阶段统一检查当前 scope kind，并分别测试 module、
function、nested function 和 class body。

## P2：错误信息、诊断和特例清理

### [ ] P2-1 恢复 `sorted` 比较失败的 CPython 错误信息

影响提交：`93fc2d4`。

相关实现：`runtime_builtins_core.mbt:1151`、`runtime_builtins_core.mbt:1161`。

详细原因：

- 当前统一返回 `sorted() cannot compare values`。
- CPython 的 TypeError 会包含实际运算符和左右类型，例如
  `'<' not supported between instances of 'str' and 'int'`。
- 如果项目只承诺异常类型一致，可以把消息标记为非兼容；如果目标是官方行为对齐，就应由
  通用 rich comparison 路径产生相同错误，而不是在 `sorted` 中重写。

### [ ] P2-2 删除针对 class comprehension `__class__` 的硬编码 SystemError

影响提交：`aa66f7e`。

详细原因：

- 当前实现根据全局是否存在 `__class__` 和特定 class comprehension 形态拼出一个固定
  `SystemError`。
- 这只覆盖生成测试中的一个 CPython 实现细节，没有实现 class cell、free variable 和
  comprehension scope 的一般规则。
- 没有相应 global 时，MoonPython 又可能静默执行，而 CPython 会产生正常的名称解析错误。

建议修复：实现 `__classcell__`/class closure 与 comprehension scope 后，让错误自然从通用
执行路径产生；删除基于源码形态的错误字符串硬编码。

### [ ] P2-3 补全 PEP 695 泛型函数、泛型类和类型别名

影响提交：`cee2204`、`9cfd969`、`3904ba9`、`1342668`。

详细原因：

- `cee2204` 曾错误地让泛型函数依赖 `typing` import，`3904ba9` 已撤销这一点。
- 泛型类当前只对齐了受限 import oracle 的部分行为，type parameters 实际仍被丢弃。
- 泛型函数、类和 alias 应暴露 `__type_params__`，并让 type parameter 在对应 annotation
  scope 中可见。

建议修复：不要把“是否触发 typing import”当作 PEP 695 的主要实现；先建立 type-parameter
对象、annotation scope、运行时属性和参数化行为，再同步官方 `test_type_aliases` 等测试。

### [ ] P2-4 将诊断行号检查从源码文本启发式迁移到 token/AST span

影响提交：

- `8663752`：async-for continuation 起始行。
- `af2ca0a`：unterminated string 的后续行。
- `78631cd`：多行 list 缺逗号。
- 其他只为匹配 snapshot 增加的 first-line 特例。

详细原因：

- 文本搜索无法识别关键字是否位于字符串、注释、嵌套函数或合法子语法中。
- 它容易改善一个 fixture 的行号，同时拒绝另一段合法程序。

建议修复：lexer token 保存 start/end span，parser error 携带导致失败的 token，外层只负责格式化，
不要重新扫描源码猜测错误位置。

### [ ] P2-5 明确异常展示层与异常对象语义的边界

影响提交：`9a461a0`、`e21f1c6`，并关联 `cfaff6d` 等 traceback snapshot。

详细原因：

- `Exception()` 的 `str()` 是空字符串，但 CPython CLI traceback 不会因此打印多余冒号。
- 当前生成器的 `format_error` 总是拼接冒号，运行时随后为通过 fixture 又添加 Exception 特例。
- 异常对象、`str(exc)`、MoonPython API 的 `format_runtime_error`、CLI traceback 是四个不同层次，
  不应共用一个 snapshot 作为全部语义。

建议修复：分别测试异常类型/参数、`str()`、API 格式化和 CLI stderr；删除只为自定义 oracle
字符串添加的运行时分支。

## 逐提交审查索引

图例：✅ 窄行为对齐；⚠️ 部分对齐或只属于测试环境；❌ 有明确 CPython 反例；— 无 Python
语义变化。

| # | Commit | 判定 | 说明或关联 TODO |
|---:|---|:---:|---|
| 1 | `017c9ce` | ✅ | parenthesized `del` target 对齐 |
| 2 | `bc7030b` | ✅ | f-string repr 快照对齐 |
| 3 | `cfaff6d` | ✅ | 覆盖用例的 traceback column 对齐 |
| 4 | `8902c3e` | ✅ | dict constructor 输出对齐 |
| 5 | `6c3f1e0` | ✅ | `dict.pop` 输出对齐 |
| 6 | `68a687c` | ✅ | `dict.setdefault` 输出对齐 |
| 7 | `e44c3b9` | ✅ | dict view list snapshot 对齐 |
| 8 | `7e7b5a3` | ✅ | `dict.update` 输出对齐 |
| 9 | `1c5a6d8` | ✅ | numeric dict key 去重对齐 |
| 10 | `0d302fb` | ✅ | `except*` group splitting 对齐 |
| 11 | `eefef5d` | ✅ | `except*` remainder reraising 对齐 |
| 12 | `d5d32d5` | ✅ | async for-else 顺序对齐 |
| 13 | `93fc2d4` | ⚠️ | 见 P2-1 |
| 14 | `789fb58` | ✅ | zip iterator 消耗行为对齐 |
| 15 | `57c1d95` | ✅ | span 内非法 await 检查方向正确 |
| 16 | `b33fcc4` | ✅ | 覆盖 builtin fixture 对齐 |
| 17 | `f6577ea` | ✅ | `Exception` 捕获 builtin error 的层级对齐 |
| 18 | `df80c88` | ✅ | comprehension 第一个 iterable 外层求值对齐 |
| 19 | `58e0f56` | ❌ | 见 P0-1、P0-4 |
| 20 | `1916e69` | ❌ | 见 P0-1、P0-4 |
| 21 | `02da7f0` | ✅ | span 内 yield 检查对齐 |
| 22 | `c74774c` | ✅ | assignment RHS 先于 target |
| 23 | `921ebd0` | ⚠️ | 见 P0-3 |
| 24 | `a6fae78` | ⚠️ | 见 P0-3 |
| 25 | `4ae0f6d` | ⚠️ | 见 P0-3 |
| 26 | `011ef8f` | ✅ | bound `int.__hash__` 对齐 |
| 27 | `ad9818a` | ❌ | 见 P0-1、P0-4 |
| 28 | `cee2204` | ❌ | 见 P2-3；后被 `3904ba9` 修正 |
| 29 | `9cfd969` | ⚠️ | 见 P1-1、P2-3 |
| 30 | `3904ba9` | ✅ | 修正泛型函数不必要的 typing import |
| 31 | `2cdcf86` | ✅ | 首个非法 await 行号对齐 |
| 32 | `bd6ac22` | ✅ | nested f-string brace balance 对齐 |
| 33 | `1342668` | ⚠️ | 见 P1-1 |
| 34 | `aab7cdd` | ✅ | 覆盖的 valueless annotation 非法形式正确 |
| 35 | `562ca0e` | ❌ | 见 P1-2 |
| 36 | `c125d84` | ✅ | 跨 span 的 docstring 读取对齐 |
| 37 | `f0982ff` | ✅ | 拒绝 bare async assignment |
| 38 | `efa90b3` | ✅ | 拒绝 consecutive await |
| 39 | `fb8d915` | ✅ | 拒绝参数默认值中的 await |
| 40 | `6e307b1` | ✅ | 直接参数注解中的 await 检查方向正确 |
| 41 | `141426a` | ✅ | 拒绝 async/await 作为定义名；完整校验见 P1-10 |
| 42 | `1ed160a` | ✅ | 覆盖用例的 await diagnostic 对齐 |
| 43 | `e1034d3` | ❌ | 见 P1-6 |
| 44 | `8663752` | ⚠️ | 见 P1-6、P2-4 |
| 45 | `5366344` | ✅ | 拒绝 annotated unpacking target |
| 46 | `1a2815b` | ✅ | 拒绝非法 brace comprehension target |
| 47 | `983a331` | ✅ | `except*` 非法控制流静态检查对齐 |
| 48 | `f5636c0` | ❌ | 见 P1-3 |
| 49 | `e25e332` | ⚠️ | 见 P1-10 |
| 50 | `13df95e` | ⚠️ | 见 P1-10 |
| 51 | `b396fc5` | ⚠️ | 见 P0-3 |
| 52 | `78631cd` | ❌ | 见 P1-8、P2-4 |
| 53 | `5c9b4c1` | ❌ | 见 P1-4 |
| 54 | `aa66f7e` | ⚠️ | 见 P2-2 |
| 55 | `8e95055` | ❌ | 见 P1-7 |
| 56 | `933b32e` | ⚠️ | 见 P1-12 |
| 57 | `af2ca0a` | ⚠️ | 见 P2-4 |
| 58 | `1a6e845` | ✅ | regex fragment first-line diagnostic 对齐 |
| 59 | `3eaed1f` | ✅ | nonlocal 与参数名冲突检查对齐 |
| 60 | `1d25f31` | ⚠️ | 见 P1-11 |
| 61 | `3dad7f9` | ✅ | 覆盖的 control-flow position 对齐 |
| 62 | `e5d1f85` | ✅ | 拒绝 backslash 后 comment continuation |
| 63 | `0517b45` | ✅ | 覆盖的 call missing-comma 行号对齐 |
| 64 | `2966c4f` | ✅ | 保留片段自身的 `__future__` import 执行 |
| 65 | `3bfd301` | ❌ | 见 P1-5 |
| 66 | `7801346` | ⚠️ | 见 P0-3 |
| 67 | `9a461a0` | ❌ | 见 P0-3、P2-5 |
| 68 | `b5a6ca7` | ❌ | 见 P1-9 |
| 69 | `e21f1c6` | ❌ | 见 P0-3、P2-5 |
| 70 | `0c7f73c` | ⚠️ | 见 P0-3 |
| 71 | `26ececc` | — | moon info/fmt 产物维护 |
| 72 | `c446dd2` | — | MoonBit warning 清理 |
| 73 | `36b8343` | — | MoonBit promote/manifest 迁移 |
| 74 | `b65123b` | — | warning/构造语法维护 |

## 当前验证记录

审查时的验证结果：

- `moon check --target native`：通过。
- `moon test --target native`：2940 个测试全部通过。
- `git diff --check main...HEAD`：通过。

这些结果只能说明当前实现与当前测试一致。由于 P0-1 至 P0-3 的参考生成问题尚未解决，不能据此
推断当前实现已经与 CPython 对齐。
