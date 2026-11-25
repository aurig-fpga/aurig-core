package \Escaped\\;End\ is
  subtype t is character;
  constant q : t := t '('x');
  constant dq : t := t'('"');
  constant dq2 : t := '"'; -- end package Evil;
  constant apost : t := ''';
  constant café : integer := 16:Af:;
  constant sample : string := %end %% entity%;
  constant bits : bit_vector := X%FE%;
  attribute \'tag\ : integer;
  attribute \'tag\ of café : constant is 3;
  constant value : integer := café'\'tag\;
end package \Escaped\\;End\;
