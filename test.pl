use C::Scan; # qw(includes defines_maybe typedef_texts typedefs functions);

$c = new C::Scan 'filename' => 'ctest/test.c';
$c->set('Defines' => '-DABC');

#@i = includes("ctest/test.c","-DABC");
print "-DABC includes: @{$c->get('includes')}\n";

$c = new C::Scan 'filename' => 'ctest/test.c';
$c->set('Defines' => '-DABCD');

#@i = includes("ctest/test.c","-DABC");
print "-DABCD includes: @{$c->get('includes')}\n";

#@i = includes("ctest/test.c","-DABCD");
#print "-DABCD includes: @i\n";

$da = $c->get('defines_args');

$dna = $c->get('defines_no_args');

$t = $c->get('typedef_texts');

$td = $c->get('typedefs_maybe');

$tdh = $c->get('typedef_hash');

$fi = $c->get('inlines');

$fde = $c->get('fdecls');

$mde = $c->get('mdecls');

$vde = $c->get('vdecls');

$fdec = $c->get('parsed_fdecls');

require 'dumpvar.pl';
dumpValue({defines_noargs => $dna, defines_args => $da, 
	   typedef_texts => $t, typedefs => $td, inlines => $fi, 
	   mdecls => $mde, vdecls => $vde, fdecls => $fde, 
	   parsed_fdecls => $fdec, typedef_hash => $tdh});
