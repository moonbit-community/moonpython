"""Minimal pure-Python fallback for _ast."""

PyCF_ALLOW_TOP_LEVEL_AWAIT = 8192
PyCF_ONLY_AST = 1024
PyCF_OPTIMIZED_AST = 33792
PyCF_TYPE_COMMENTS = 4096

class AST:
    _fields = ()
    _attributes = ()
    def __init__(self, *args, **kwargs):
        for name, value in zip(self._fields, args):
            setattr(self, name, value)
        for name, value in kwargs.items():
            setattr(self, name, value)

class mod(AST):
    _fields = ()
    _attributes = ()

class stmt(AST):
    _fields = ()
    _attributes = ('lineno', 'col_offset', 'end_lineno', 'end_col_offset')

class expr(AST):
    _fields = ()
    _attributes = ('lineno', 'col_offset', 'end_lineno', 'end_col_offset')

class expr_context(AST):
    _fields = ()
    _attributes = ()

class boolop(AST):
    _fields = ()
    _attributes = ()

class operator(AST):
    _fields = ()
    _attributes = ()

class unaryop(AST):
    _fields = ()
    _attributes = ()

class cmpop(AST):
    _fields = ()
    _attributes = ()

class comprehension(AST):
    _fields = ('target', 'iter', 'ifs', 'is_async')
    _attributes = ()

class excepthandler(AST):
    _fields = ()
    _attributes = ('lineno', 'col_offset', 'end_lineno', 'end_col_offset')

class arguments(AST):
    _fields = ('posonlyargs', 'args', 'vararg', 'kwonlyargs', 'kw_defaults', 'kwarg', 'defaults')
    _attributes = ()

class arg(AST):
    _fields = ('arg', 'annotation', 'type_comment')
    _attributes = ('lineno', 'col_offset', 'end_lineno', 'end_col_offset')

class keyword(AST):
    _fields = ('arg', 'value')
    _attributes = ('lineno', 'col_offset', 'end_lineno', 'end_col_offset')

class alias(AST):
    _fields = ('name', 'asname')
    _attributes = ('lineno', 'col_offset', 'end_lineno', 'end_col_offset')

class withitem(AST):
    _fields = ('context_expr', 'optional_vars')
    _attributes = ()

class match_case(AST):
    _fields = ('pattern', 'guard', 'body')
    _attributes = ()

class pattern(AST):
    _fields = ()
    _attributes = ('lineno', 'col_offset', 'end_lineno', 'end_col_offset')

class type_ignore(AST):
    _fields = ()
    _attributes = ()

class type_param(AST):
    _fields = ()
    _attributes = ('lineno', 'col_offset', 'end_lineno', 'end_col_offset')

class slice(AST):
    _fields = ()
    _attributes = ()

class Module(mod):
    _fields = ('body', 'type_ignores')
    _attributes = ()

class Interactive(mod):
    _fields = ('body',)
    _attributes = ()

class Expression(mod):
    _fields = ('body',)
    _attributes = ()

class FunctionType(mod):
    _fields = ('argtypes', 'returns')
    _attributes = ()

class FunctionDef(stmt):
    _fields = ('name', 'args', 'body', 'decorator_list', 'returns', 'type_comment', 'type_params')
    _attributes = ('lineno', 'col_offset', 'end_lineno', 'end_col_offset')

class AsyncFunctionDef(stmt):
    _fields = ('name', 'args', 'body', 'decorator_list', 'returns', 'type_comment', 'type_params')
    _attributes = ('lineno', 'col_offset', 'end_lineno', 'end_col_offset')

class ClassDef(stmt):
    _fields = ('name', 'bases', 'keywords', 'body', 'decorator_list', 'type_params')
    _attributes = ('lineno', 'col_offset', 'end_lineno', 'end_col_offset')

class Return(stmt):
    _fields = ('value',)
    _attributes = ('lineno', 'col_offset', 'end_lineno', 'end_col_offset')

class Delete(stmt):
    _fields = ('targets',)
    _attributes = ('lineno', 'col_offset', 'end_lineno', 'end_col_offset')

class Assign(stmt):
    _fields = ('targets', 'value', 'type_comment')
    _attributes = ('lineno', 'col_offset', 'end_lineno', 'end_col_offset')

class TypeAlias(stmt):
    _fields = ('name', 'type_params', 'value')
    _attributes = ('lineno', 'col_offset', 'end_lineno', 'end_col_offset')

class AugAssign(stmt):
    _fields = ('target', 'op', 'value')
    _attributes = ('lineno', 'col_offset', 'end_lineno', 'end_col_offset')

class AnnAssign(stmt):
    _fields = ('target', 'annotation', 'value', 'simple')
    _attributes = ('lineno', 'col_offset', 'end_lineno', 'end_col_offset')

class For(stmt):
    _fields = ('target', 'iter', 'body', 'orelse', 'type_comment')
    _attributes = ('lineno', 'col_offset', 'end_lineno', 'end_col_offset')

class AsyncFor(stmt):
    _fields = ('target', 'iter', 'body', 'orelse', 'type_comment')
    _attributes = ('lineno', 'col_offset', 'end_lineno', 'end_col_offset')

class While(stmt):
    _fields = ('test', 'body', 'orelse')
    _attributes = ('lineno', 'col_offset', 'end_lineno', 'end_col_offset')

class If(stmt):
    _fields = ('test', 'body', 'orelse')
    _attributes = ('lineno', 'col_offset', 'end_lineno', 'end_col_offset')

class With(stmt):
    _fields = ('items', 'body', 'type_comment')
    _attributes = ('lineno', 'col_offset', 'end_lineno', 'end_col_offset')

class AsyncWith(stmt):
    _fields = ('items', 'body', 'type_comment')
    _attributes = ('lineno', 'col_offset', 'end_lineno', 'end_col_offset')

class Match(stmt):
    _fields = ('subject', 'cases')
    _attributes = ('lineno', 'col_offset', 'end_lineno', 'end_col_offset')

class Raise(stmt):
    _fields = ('exc', 'cause')
    _attributes = ('lineno', 'col_offset', 'end_lineno', 'end_col_offset')

class Try(stmt):
    _fields = ('body', 'handlers', 'orelse', 'finalbody')
    _attributes = ('lineno', 'col_offset', 'end_lineno', 'end_col_offset')

class TryStar(stmt):
    _fields = ('body', 'handlers', 'orelse', 'finalbody')
    _attributes = ('lineno', 'col_offset', 'end_lineno', 'end_col_offset')

class Assert(stmt):
    _fields = ('test', 'msg')
    _attributes = ('lineno', 'col_offset', 'end_lineno', 'end_col_offset')

class Import(stmt):
    _fields = ('names',)
    _attributes = ('lineno', 'col_offset', 'end_lineno', 'end_col_offset')

class ImportFrom(stmt):
    _fields = ('module', 'names', 'level')
    _attributes = ('lineno', 'col_offset', 'end_lineno', 'end_col_offset')

class Global(stmt):
    _fields = ('names',)
    _attributes = ('lineno', 'col_offset', 'end_lineno', 'end_col_offset')

class Nonlocal(stmt):
    _fields = ('names',)
    _attributes = ('lineno', 'col_offset', 'end_lineno', 'end_col_offset')

class Expr(stmt):
    _fields = ('value',)
    _attributes = ('lineno', 'col_offset', 'end_lineno', 'end_col_offset')

class Pass(stmt):
    _fields = ()
    _attributes = ('lineno', 'col_offset', 'end_lineno', 'end_col_offset')

class Break(stmt):
    _fields = ()
    _attributes = ('lineno', 'col_offset', 'end_lineno', 'end_col_offset')

class Continue(stmt):
    _fields = ()
    _attributes = ('lineno', 'col_offset', 'end_lineno', 'end_col_offset')

class BoolOp(expr):
    _fields = ('op', 'values')
    _attributes = ('lineno', 'col_offset', 'end_lineno', 'end_col_offset')

class NamedExpr(expr):
    _fields = ('target', 'value')
    _attributes = ('lineno', 'col_offset', 'end_lineno', 'end_col_offset')

class BinOp(expr):
    _fields = ('left', 'op', 'right')
    _attributes = ('lineno', 'col_offset', 'end_lineno', 'end_col_offset')

class UnaryOp(expr):
    _fields = ('op', 'operand')
    _attributes = ('lineno', 'col_offset', 'end_lineno', 'end_col_offset')

class Lambda(expr):
    _fields = ('args', 'body')
    _attributes = ('lineno', 'col_offset', 'end_lineno', 'end_col_offset')

class IfExp(expr):
    _fields = ('test', 'body', 'orelse')
    _attributes = ('lineno', 'col_offset', 'end_lineno', 'end_col_offset')

class Dict(expr):
    _fields = ('keys', 'values')
    _attributes = ('lineno', 'col_offset', 'end_lineno', 'end_col_offset')

class Set(expr):
    _fields = ('elts',)
    _attributes = ('lineno', 'col_offset', 'end_lineno', 'end_col_offset')

class ListComp(expr):
    _fields = ('elt', 'generators')
    _attributes = ('lineno', 'col_offset', 'end_lineno', 'end_col_offset')

class SetComp(expr):
    _fields = ('elt', 'generators')
    _attributes = ('lineno', 'col_offset', 'end_lineno', 'end_col_offset')

class DictComp(expr):
    _fields = ('key', 'value', 'generators')
    _attributes = ('lineno', 'col_offset', 'end_lineno', 'end_col_offset')

class GeneratorExp(expr):
    _fields = ('elt', 'generators')
    _attributes = ('lineno', 'col_offset', 'end_lineno', 'end_col_offset')

class Await(expr):
    _fields = ('value',)
    _attributes = ('lineno', 'col_offset', 'end_lineno', 'end_col_offset')

class Yield(expr):
    _fields = ('value',)
    _attributes = ('lineno', 'col_offset', 'end_lineno', 'end_col_offset')

class YieldFrom(expr):
    _fields = ('value',)
    _attributes = ('lineno', 'col_offset', 'end_lineno', 'end_col_offset')

class Compare(expr):
    _fields = ('left', 'ops', 'comparators')
    _attributes = ('lineno', 'col_offset', 'end_lineno', 'end_col_offset')

class Call(expr):
    _fields = ('func', 'args', 'keywords')
    _attributes = ('lineno', 'col_offset', 'end_lineno', 'end_col_offset')

class FormattedValue(expr):
    _fields = ('value', 'conversion', 'format_spec')
    _attributes = ('lineno', 'col_offset', 'end_lineno', 'end_col_offset')

class Interpolation(expr):
    _fields = ('value', 'str', 'conversion', 'format_spec')
    _attributes = ('lineno', 'col_offset', 'end_lineno', 'end_col_offset')

class JoinedStr(expr):
    _fields = ('values',)
    _attributes = ('lineno', 'col_offset', 'end_lineno', 'end_col_offset')

class TemplateStr(expr):
    _fields = ('values',)
    _attributes = ('lineno', 'col_offset', 'end_lineno', 'end_col_offset')

class Constant(expr):
    _fields = ('value', 'kind')
    _attributes = ('lineno', 'col_offset', 'end_lineno', 'end_col_offset')

class Attribute(expr):
    _fields = ('value', 'attr', 'ctx')
    _attributes = ('lineno', 'col_offset', 'end_lineno', 'end_col_offset')

class Subscript(expr):
    _fields = ('value', 'slice', 'ctx')
    _attributes = ('lineno', 'col_offset', 'end_lineno', 'end_col_offset')

class Starred(expr):
    _fields = ('value', 'ctx')
    _attributes = ('lineno', 'col_offset', 'end_lineno', 'end_col_offset')

class Name(expr):
    _fields = ('id', 'ctx')
    _attributes = ('lineno', 'col_offset', 'end_lineno', 'end_col_offset')

class List(expr):
    _fields = ('elts', 'ctx')
    _attributes = ('lineno', 'col_offset', 'end_lineno', 'end_col_offset')

class Tuple(expr):
    _fields = ('elts', 'ctx')
    _attributes = ('lineno', 'col_offset', 'end_lineno', 'end_col_offset')

class Slice(expr):
    _fields = ('lower', 'upper', 'step')
    _attributes = ('lineno', 'col_offset', 'end_lineno', 'end_col_offset')

class Load(expr_context):
    _fields = ()
    _attributes = ()

class Store(expr_context):
    _fields = ()
    _attributes = ()

class Del(expr_context):
    _fields = ()
    _attributes = ()

class And(boolop):
    _fields = ()
    _attributes = ()

class Or(boolop):
    _fields = ()
    _attributes = ()

class Add(operator):
    _fields = ()
    _attributes = ()

class Sub(operator):
    _fields = ()
    _attributes = ()

class Mult(operator):
    _fields = ()
    _attributes = ()

class MatMult(operator):
    _fields = ()
    _attributes = ()

class Div(operator):
    _fields = ()
    _attributes = ()

class Mod(operator):
    _fields = ()
    _attributes = ()

class Pow(operator):
    _fields = ()
    _attributes = ()

class LShift(operator):
    _fields = ()
    _attributes = ()

class RShift(operator):
    _fields = ()
    _attributes = ()

class BitOr(operator):
    _fields = ()
    _attributes = ()

class BitXor(operator):
    _fields = ()
    _attributes = ()

class BitAnd(operator):
    _fields = ()
    _attributes = ()

class FloorDiv(operator):
    _fields = ()
    _attributes = ()

class Invert(unaryop):
    _fields = ()
    _attributes = ()

class Not(unaryop):
    _fields = ()
    _attributes = ()

class UAdd(unaryop):
    _fields = ()
    _attributes = ()

class USub(unaryop):
    _fields = ()
    _attributes = ()

class Eq(cmpop):
    _fields = ()
    _attributes = ()

class NotEq(cmpop):
    _fields = ()
    _attributes = ()

class Lt(cmpop):
    _fields = ()
    _attributes = ()

class LtE(cmpop):
    _fields = ()
    _attributes = ()

class Gt(cmpop):
    _fields = ()
    _attributes = ()

class GtE(cmpop):
    _fields = ()
    _attributes = ()

class Is(cmpop):
    _fields = ()
    _attributes = ()

class IsNot(cmpop):
    _fields = ()
    _attributes = ()

class In(cmpop):
    _fields = ()
    _attributes = ()

class NotIn(cmpop):
    _fields = ()
    _attributes = ()

class ExceptHandler(excepthandler):
    _fields = ('type', 'name', 'body')
    _attributes = ('lineno', 'col_offset', 'end_lineno', 'end_col_offset')

class MatchValue(pattern):
    _fields = ('value',)
    _attributes = ('lineno', 'col_offset', 'end_lineno', 'end_col_offset')

class MatchSingleton(pattern):
    _fields = ('value',)
    _attributes = ('lineno', 'col_offset', 'end_lineno', 'end_col_offset')

class MatchSequence(pattern):
    _fields = ('patterns',)
    _attributes = ('lineno', 'col_offset', 'end_lineno', 'end_col_offset')

class MatchMapping(pattern):
    _fields = ('keys', 'patterns', 'rest')
    _attributes = ('lineno', 'col_offset', 'end_lineno', 'end_col_offset')

class MatchClass(pattern):
    _fields = ('cls', 'patterns', 'kwd_attrs', 'kwd_patterns')
    _attributes = ('lineno', 'col_offset', 'end_lineno', 'end_col_offset')

class MatchStar(pattern):
    _fields = ('name',)
    _attributes = ('lineno', 'col_offset', 'end_lineno', 'end_col_offset')

class MatchAs(pattern):
    _fields = ('pattern', 'name')
    _attributes = ('lineno', 'col_offset', 'end_lineno', 'end_col_offset')

class MatchOr(pattern):
    _fields = ('patterns',)
    _attributes = ('lineno', 'col_offset', 'end_lineno', 'end_col_offset')

class TypeIgnore(type_ignore):
    _fields = ('lineno', 'tag')
    _attributes = ()

class TypeVar(type_param):
    _fields = ('name', 'bound', 'default_value')
    _attributes = ('lineno', 'col_offset', 'end_lineno', 'end_col_offset')

class ParamSpec(type_param):
    _fields = ('name', 'default_value')
    _attributes = ('lineno', 'col_offset', 'end_lineno', 'end_col_offset')

class TypeVarTuple(type_param):
    _fields = ('name', 'default_value')
    _attributes = ('lineno', 'col_offset', 'end_lineno', 'end_col_offset')

class Index(slice):
    _fields = ()
    _attributes = ()

class ExtSlice(slice):
    _fields = ()
    _attributes = ()

class Suite(mod):
    _fields = ()
    _attributes = ()

class AugLoad(expr_context):
    _fields = ()
    _attributes = ()

class AugStore(expr_context):
    _fields = ()
    _attributes = ()

class Param(expr_context):
    _fields = ()
    _attributes = ()

__all__ = [
    'AST',
    'mod',
    'stmt',
    'expr',
    'expr_context',
    'boolop',
    'operator',
    'unaryop',
    'cmpop',
    'comprehension',
    'excepthandler',
    'arguments',
    'arg',
    'keyword',
    'alias',
    'withitem',
    'match_case',
    'pattern',
    'type_ignore',
    'type_param',
    'slice',
    'Module',
    'Interactive',
    'Expression',
    'FunctionType',
    'FunctionDef',
    'AsyncFunctionDef',
    'ClassDef',
    'Return',
    'Delete',
    'Assign',
    'TypeAlias',
    'AugAssign',
    'AnnAssign',
    'For',
    'AsyncFor',
    'While',
    'If',
    'With',
    'AsyncWith',
    'Match',
    'Raise',
    'Try',
    'TryStar',
    'Assert',
    'Import',
    'ImportFrom',
    'Global',
    'Nonlocal',
    'Expr',
    'Pass',
    'Break',
    'Continue',
    'BoolOp',
    'NamedExpr',
    'BinOp',
    'UnaryOp',
    'Lambda',
    'IfExp',
    'Dict',
    'Set',
    'ListComp',
    'SetComp',
    'DictComp',
    'GeneratorExp',
    'Await',
    'Yield',
    'YieldFrom',
    'Compare',
    'Call',
    'FormattedValue',
    'Interpolation',
    'JoinedStr',
    'TemplateStr',
    'Constant',
    'Attribute',
    'Subscript',
    'Starred',
    'Name',
    'List',
    'Tuple',
    'Slice',
    'Load',
    'Store',
    'Del',
    'And',
    'Or',
    'Add',
    'Sub',
    'Mult',
    'MatMult',
    'Div',
    'Mod',
    'Pow',
    'LShift',
    'RShift',
    'BitOr',
    'BitXor',
    'BitAnd',
    'FloorDiv',
    'Invert',
    'Not',
    'UAdd',
    'USub',
    'Eq',
    'NotEq',
    'Lt',
    'LtE',
    'Gt',
    'GtE',
    'Is',
    'IsNot',
    'In',
    'NotIn',
    'ExceptHandler',
    'MatchValue',
    'MatchSingleton',
    'MatchSequence',
    'MatchMapping',
    'MatchClass',
    'MatchStar',
    'MatchAs',
    'MatchOr',
    'TypeIgnore',
    'TypeVar',
    'ParamSpec',
    'TypeVarTuple',
    'Index',
    'ExtSlice',
    'Suite',
    'AugLoad',
    'AugStore',
    'Param',
    'PyCF_ALLOW_TOP_LEVEL_AWAIT',
    'PyCF_ONLY_AST',
    'PyCF_OPTIMIZED_AST',
    'PyCF_TYPE_COMMENTS',
]
