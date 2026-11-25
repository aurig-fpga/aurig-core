package counters is
  type counter is protected
    procedure increment;
  end protected counter;
end package;
package body counters is
  type counter is protected body
    procedure increment is begin null; end increment;
  end protected body counter;
end package body;
