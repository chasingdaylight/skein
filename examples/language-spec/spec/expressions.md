# Expressions

This chapter specifies the expressions of a small calculator language. Text without a marker, like this paragraph, is narrative: it explains, and is not a rule.

## Terms

%term[expr.operand]
An operand is a number or an expression in parentheses.

%term[expr.value]
The value of an expression is the number that evaluating it gives.

## Numbers

%rule[expr.number.syntax syntax stage=core]
A number is one or more decimal digits, optionally followed by a point and one or more decimal digits.

```text
number = digit { digit } [ "." digit { digit } ] ;
```

%rule[expr.number.value dynamic stage=core]
The [[expr.value|value]] of a number is the number its digits spell in base ten.

## Operators

%rule[expr.binary.syntax syntax stage=core]
A binary expression is two [[expr.operand|operands]] with one of these operators between them:

- `+` and `-`
- `*` and `/`

%rule[expr.binary.precedence syntax stage=core]
`*` and `/` bind tighter than `+` and `-`. Operators that bind equally group from the left.

%rule[expr.divide.zero dynamic stage=core]
Dividing by zero stops the evaluation with an error; it has no [[expr.value]].

%rule[expr.power.syntax syntax stage=full]
A power expression is two [[expr.operand|operands]] with `^` between them. It binds tighter than `*` and groups from the right.

%rule[expr.power.negative legality stage=full]
The exponent of a power expression must not be a negative number written as a literal.

%rule[expr.modulo removed]

The modulo operator was removed before the first release. Its marker stays, so that its ID is never given to another rule.
