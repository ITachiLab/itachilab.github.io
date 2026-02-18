parser grammar BfaParser;

options { tokenVocab=BfaLexer; }

source
  : dataSection? codeSection
  ;

dataSection
  : DATA_SECTION dataEntry+
  ;

dataEntry
  : VARIABLE_ID ASSIGNMENT (DECIMAL_VALUE | HEX_VALUE | BIN_VALUE)
  ;

codeSection
  : TEXT_SECTION instruction+
  ;

instruction
  : MNEMONIC_MOV OPERAND_REG0 OPERAND_DELIM OPERAND_CONST
  | MNEMONIC_MOV OPERAND_REG0 OPERAND_DELIM operandMemDereference
  | MNEMONIC_MOV OPERAND_REG0 OPERAND_DELIM OPERAND_MEM_ADDRESS
  ;

operandMemDereference
  : MEM_POINTER MEM_MINUS_PLUS MEM_OFFSET
  ;
