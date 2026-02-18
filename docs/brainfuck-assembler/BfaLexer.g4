lexer grammar BfaLexer;

SECTION_PREFIX : '.' -> more, pushMode(SECTION);
WS  : [ \r\t\n]+ -> skip;

mode SECTION;

DATA_SECTION  : 'data' -> pushMode(DATA);
TEXT_SECTION  : 'text' -> pushMode(TEXT);
SECTION_WS    : [ \r\t\n]+ -> skip;

mode DATA;

VARIABLE_ID   : [a-zA-Z] [a-zA-Z0-9]*;
ASSIGNMENT    : '=';
DECIMAL_VALUE : [0-9]+;
HEX_VALUE     : '0x' [0-9a-fA-F]+;
BIN_VALUE     : '0b' [01]+;
DATA_END      : '.' -> more, popMode;
DATA_WS       : [ \r\t\n]+ -> skip;

mode TEXT;

MNEMONIC_MOV    : 'mov' -> pushMode(INSTRUCTION);
MNEMONIC_PUSH   : 'push' -> pushMode(INSTRUCTION);
MNEMONIC_POP    : 'pop' -> pushMode(INSTRUCTION);
MNEMONIC_ZERO   : 'zero' -> pushMode(INSTRUCTION);
TEXT_END        : '.' -> skip, popMode;
TEXT_WS         : [ \r\t\n]+ -> skip;

mode INSTRUCTION;

OPERAND_REG0            : 'r0';
OPERAND_CONST           : [0-9]+;
OPERAND_DELIM           : ',';
OPERAND_MEM_DEREF_BEGIN : '[' -> skip, pushMode(MEM_REF);
OPERAND_MEM_ADDRESS     : '$' [a-zA-Z] [a-zA-Z0-9]*;
INSTRUCTION_END         : '\r'?'\n' -> skip, popMode;
INSTRUCTION_WS          : [ \t]+ -> skip;

mode MEM_REF;

MEM_POINTER           : '$' [a-zA-Z] [a-zA-Z0-9]*;
MEM_MINUS_PLUS        : '-' | '+';
MEM_OFFSET            : [0-9]+;
OPERAND_MEM_DEREF_END : ']' -> skip, popMode;
MEM_REF_WS            : [ \r\t\n]+ -> skip;
