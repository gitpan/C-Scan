package C::Scan;

require Exporter;
use Config '%Config';
use File::Basename;
use Data::Flow qw(0.05);
use strict;			# Earlier it catches ISA and EXPORT.

@C::Scan::ISA = qw(Exporter Data::Flow);

# Items to export into callers namespace by default. Note: do not export
# names by default without a very good reason. Use EXPORT_OK instead.
# Do not simply export all your public functions/methods/constants.

@C::Scan::EXPORT = qw(
	    );
@C::Scan::EXPORT_OK = qw(
			);
# this flag tells cpp to only output macros
$C::Scan::MACROS_ONLY = '-dM';

$C::Scan::VERSION = '0.6';

my (%keywords,%style_keywords);
for (qw(asm auto break case char continue default do double else enum
        extern float for fortran goto if int long register return short
        sizeof static struct switch typedef union unsigned signed while void)) {
  $keywords{$_}++;
}
for (qw(bool class const delete friend inline new operator overload private
        protected public virtual)) {
  $style_keywords{'C++'}{$_}++;
}
for (qw(__func__ _Complex _Imaginary _Bool inline restrict)) {
  $style_keywords{'C9X'}{$_}++;
}
for (qw(inline const asm noreturn format section 
	constructor destructor unused weak)) {
  $style_keywords{'GNU'}{$_}++;
  $style_keywords{'GNU'}{"__$ {_}__"}++;
}
  $style_keywords{'GNU'}{__attribute__}++;
  $style_keywords{'GNU'}{__extension__}++;
  $style_keywords{'GNU'}{__consts}++;
  $style_keywords{'GNU'}{__const}++;

my $recipes
  = { Defines => { default => '' },
      cppstdin => { default => $Config{cppstdin} },
      cppflags => { default => $Config{cppflags} },
      cppminus => { default => $Config{cppminus} },
      c_styles => { default => [qw(C++ GNU C9X)] },
      add_cppflags => { default => '' },
      keywords => { prerequisites => ['c_styles'],
		    output => sub {
		      my %kw = %keywords;
		      my %add;
		      for ( @{ shift->{c_styles} } ) {
			%add = %{ $style_keywords{$_} };
			%kw = (%kw, %add);
		      }
		      \%kw;
		    }, },
      'undef' => { default => undef },
      filename_filter => { default => undef },
      full_text => { class_filter => [ 'text', 'C::Preprocessed',
				       qw(undef filename Defines includeDirs Cpp)] },
      text => { class_filter => [ 'text', 'C::Preprocessed',
				  qw(filename_filter filename Defines includeDirs Cpp)] },
      text_only_from => { class_filter => [ 'text_only_from', 'C::Preprocessed',
					    qw(filename_filter filename Defines includeDirs Cpp)] },
      includes => { filter => [ \&includes, 
				qw(filename Defines includeDirs Cpp) ], },
      includeDirs =>  { prerequisites => ['filedir'], 
			output => sub {
			  my $data = shift;
			  [ $data->{filedir}, '/usr/local/include', '.'];
			} },
      Cpp => { prerequisites => [qw(cppminus add_cppflags cppflags cppstdin)], 
	       output => sub {
		 my $data = shift;
		 return { cppstdin => $data->{cppstdin},
			  cppflags => "$data->{cppflags} $data->{add_cppflags}",
			  cppminus => $data->{cppminus} };
	       } },
      filedir => { output => sub { dirname ( shift->{filename} || '.' ) } },
      sanitized => { filter => [ \&sanitize, 'text'], },
      toplevel => { filter => [ \&top_level, 'sanitized'], },
      full_sanitized => { filter => [ \&sanitize, 'full_text'], },
      full_toplevel => { filter => [ \&top_level, 'full_sanitized'], },
      no_type_decl => { filter => [ \&remove_type_decl, 'toplevel'], },
      typedef_chunks => { filter => [ \&typedef_chunks, 'full_toplevel'], },
      typedefs_maybe => { filter => [ \&typedefs_maybe, 
				      'full_sanitized', 'typedef_chunks'], },
      typedef_texts => { filter => [ \&typedef_texts, 
				      'full_text', 'typedef_chunks'], },
      typedef_hash => { prerequisites => ['typedefs_maybe'],
			output => sub { my %h; 
					for (@{$_[0]->{typedefs_maybe}}) {
					  $h{$_}++;
					}
					\%h;
				      }, },
      defines_maybe => { filter => [ \&defines_maybe, 'filename'], },
      defines_no_args => { prerequisites => ['defines_maybe'],
			   output => sub { shift->{defines_maybe}->[0] }, },
      defines_args => { prerequisites => ['defines_maybe'],
			output => sub { shift->{defines_maybe}->[1] }, },

      defines_full => { filter => [ \&defines_full, 
				    qw(filename Defines includeDirs Cpp) ], },
      defines_no_args_full => { prerequisites => ['defines_full'],
				output => sub { shift->{defines_full}->[0] }, },
      defines_args_full => { prerequisites => ['defines_full'],
			output => sub { shift->{defines_full}->[1] }, },

      decl_inlines => { filter => [ \&functions_in, 'no_type_decl'], },
      inline_chunks => { filter => [ sub { shift->[0] }, 'decl_inlines'], },
      inlines => { filter => [ \&from_chunks, 'inline_chunks', 'text'], },
      decl_chunks => { filter => [ sub { shift->[1] }, 'decl_inlines'], },
      decls => { filter => [ \&from_chunks, 'decl_chunks', 'text'], },
      fdecl_chunks => { filter => [ sub { shift->[4] }, 'decl_inlines'], },
      fdecls => { filter => [ \&from_chunks, 'fdecl_chunks', 'text'], },
      mdecl_chunks => { filter => [ sub { shift->[2] }, 'decl_inlines'], },
      mdecls => { filter => [ \&from_chunks, 'mdecl_chunks', 'text'], },
      vdecl_chunks => { filter => [ sub { shift->[3] }, 'decl_inlines'], },
      vdecls => { filter => [ \&from_chunks, 'vdecl_chunks', 'text'], },
      parsed_fdecls => { filter => [ \&do_declarations, 'fdecls', 
				     'typedef_hash', 'keywords'], },
    };

sub from_chunks {
  my $chunks = shift;
  my $txt = shift;
  my @out;
  my $i = 0;
  while ($i < @$chunks) {
    push @out, substr $txt, $chunks->[$i], $chunks->[ $i + 1 ] - $chunks->[$i];
    $i += 2;
  }
  \@out;
}

#sub process { request($recipes, @_) }
# Preloaded methods go here.

sub includes {
  my %seen;
  my $stream = new C::Preprocessed (@_)
    or die "Cannot open pipe from cppstdin: $!\n";
  
  while (<$stream>) {
    next unless m(^\s*\#\s*	# Leading hash
		  (line\s*)?	# 1: Optional line
		  ([0-9]+)\s*	# 2: Line number
		  (.*)		# 3: The rest
		 )x;
    my $include = $3;
    $include = $1 if $include =~ /"(.*)"/; # Filename may be in quotes
    $include =~ s,\\\\,/,g if $^O eq 'os2';
    $seen{$include}++ if $include ne "";
  }
  [keys %seen];
}

sub defines_maybe {
  my $file = shift;
  my ($mline,$line,%macros,%macrosargs,$sym,$args);
  open(C, $file) or die "Cannot open file $file: $!\n";
  while (not eof(C) and $line = <C>) {
    next unless 
      ( $line =~ s[
		   ^ \s* \# \s*	# Start of directive
		   define \s+
		   (\w+)	# 1: symbol
		   (?:
		    \( (.*?) \s* \) # 2: Minimal match for arguments
                                    # in parenths (without trailing
                                    # spaces)
		   )?		# optional, no grouping
		   \s*		# rest is the definition
		  ][]x );
    ($sym, $args) = ($1, $2);
    $mline = $';
    $mline .= <C> while not eof(C) and $mline =~ s/\\\n/\n/;
    chomp $mline;
    #print "sym: `$sym', args: `$args', mline: `$mline'\n";
    if (defined $args) {
      $macrosargs{$sym} = [ [split /\s*,\s*/, $args], $mline];
    } else {
      $macros{$sym} = $mline;
    }
  }
  close(C) or die "Cannot close file $file: $!\n";
  [\%macros, \%macrosargs];
}

sub defines_full {
  my $Cpp = $_[3];
  my ($mline,$line,%macros,%macrosargs,$sym,$args);

  # save the old cppflags and add the flag for only ouputting macro definitions
  my $old_cppstdin = $Cpp->{'cppstdin'};
  $Cpp->{'cppstdin'} = $old_cppstdin . " " . $C::Scan::MACROS_ONLY;

  my $stream = new C::Preprocessed (@_)
    or die "Cannot open pipe from cppstdin: $!\n";
  
  while (defined ($line = <$stream>)) {
    next unless 
      ( $line =~ s[
		   ^ \s* \# \s*	# Start of directive
		   define \s+
		   (\w+)	# 1: symbol
		   (?:
		    \( (.*?) \s* \) # 2: Minimal match for arguments
                                    # in parenths (without trailing
                                    # spaces)
		   )?		# optional, no grouping
		   \s*		# rest is the definition
		  ][]x );
    ($sym, $args) = ($1, $2);
    $mline = $';
    $mline .= <$stream> while ($mline =~ s/\\\n/\n/);
    chomp $mline;
#print STDERR "sym: `$sym', args: `$args', mline: `$mline'\n";
    if (defined $args) {
      $macrosargs{$sym} = [ [split /\s*,\s*/, $args], $mline];
    } else {
      $macros{$sym} = $mline;
    }
  }
  # restore the original cppflags
  $Cpp->{'cppstdin'} = $old_cppstdin;
  [\%macros, \%macrosargs];
}

# sub nexttypedef {
#   return unless $_[0] =~ /(\G|^|;)\s*typedef\b/g;
#   my $start = pos($_[0]) - 7;
#   nextsemi($_[0]);
#   my $end = pos $_[0];
#   # warn "Found `", substr($_[0], $start, $end - $start), "'\n" if $debug;
#   return $start, $end;
# }  

# sub nextsemi {
#   my $n = 0;
#   while ($_[0] =~ /([\(\{\[])|([\]\)\}])|(\;)/g) {
#     $n++ if defined $1;
#     $n-- if defined $2;
#     return if defined $3 and $n == 0;
#   }
#   die "No semicolon on the outer level";
# }

sub typedef_texts {
  my ($txt, $chunks) = (shift, shift);
  my ($b, $e, @out);
  my @in = @$chunks;
  while (($b, $e) = splice @in, 0, 2) {
    push @out, substr($txt, $b, $e - $b);
  }
  [@out];
}

sub typedef_chunks {		# Input is toplevel, output: starts and ends
  my $txt = shift;
  pos $txt = 0;
  my ($b, $e, @out);
  while ($txt =~ /\btypedef\b/g) {
    push @out, pos $txt;
    $txt =~ /;|\Z/g;
    push @out, pos $txt;
  }
  \@out;
}

# The output is the list of list of inline chunks and list of
# declaration chunks.

sub functions_in {		# The arg is text without type declarations.
  my $in = shift;		# remove_type_decl(top_level(sanitize($txt)));
  # What remains now consists of variable and function declarations,
  # and inline functions.
  $in =~ /(?=\S)/g;
  my ($b, $e, $b1, $e1, @inlines, @decls, @mdecls, @fdecls, @vdecls);
  $b = pos $in;
  my $chunk;
  while ($b != length $in) {
    $in =~ /;/g or pos $in = $b, $in =~ /.*\S|\Z/g ; # Or last non-space
    $e = pos $in;
    $chunk = substr $in, $b, $e - $b;
    # Now subdivide the chunk.
    # 
    # What we got is one chunk, probably finished by `;'. Whoever, it
    # may start with several inline functions.
    #
    # Note that inline functions contain ( ) { } in the stripped version.
    $b1 = 0;
    while ($chunk =~ /\(\s*\)\s*\{\s*\}/g) {
      $e1 = pos $chunk;
      push @inlines, $b + $b1, $b + $e1;
      $chunk =~ /(?=\S)/g;
      $b1 = pos $chunk; 
      $b1 = length $chunk, last unless defined $b1;
    }
    if ($e - $b - $b1 > 0) {
      push @decls, $b + $b1, $e;
      substr ($chunk, 0, $b1) = '';
      if ($chunk =~ /,/) {	# Contains multiple declarations.
	push @mdecls, $b + $b1, $e;
      } else  {			# Non-multiple.
	my $isvar = 1;
	$chunk =~ s{
		    \s* ( ( const
			    | __attribute__ \s* \( \s* \)
			  ) \s* )* ( ; \s* )? \Z # Strip from the end
		   }()x;
	if ($chunk =~ /\)\Z/) { # Function declaration ends on ")"!
	  if ($chunk !~ m{ 
			  \( .* \( # Multiple parenths
			 }x
	      and $chunk =~ / \w \s* \( /x) { # Most probably pointer to a function?
	    $isvar = 0;
	  }
	}
	if ($isvar)  {	# Heuristically variable
	  push @vdecls, $b + $b1, $e;
	} else {
	  push @fdecls, $b + $b1, $e;
	}
      }
    }
    $in =~ /\G\s*/g ;
    $b = pos $in;
  }
  [\@inlines, \@decls, \@mdecls, \@vdecls, \@fdecls];
}

sub typedefs_maybe {		# Input is sanitized text, and list of beg/end.
  my @lst = @{$_[1]};
  my @out;
  my ($b, $e);
  while ($b = shift @lst) {
    $e = shift @lst;
    push @out, typedef_words(substr $_[0], $b, $e - $b);
  }
  \@out;
}

sub typedef_words {		# Input is sanitized.
  my $in = shift;		# Text of typedef.
  # Remove all the structs
  my $rest  = $in;
  my $start = "";
  while ($rest =~ s/\b(struct|union|class|enum)(\s+\w+)?\s*\{//) {
    $rest = $';
    $start .= $`;
    pos $rest = 0;
    matchingbrace($rest);
    $rest = substr $rest, pos $rest;
  }
  $in = $start . $rest;

  # Deal with glibc's wierd ass __attribute__ tag.  Just dump it.
  # Maaaybe this should check to see if you're using GCC, but I don't
  # think so since glibc is nice enough to do that for you.  [MGS]
  if ( $in =~ m/\b(__attribute__|attribute)\s*\((?=\s*\()/g ) {
      my $att_pos_start = pos($in) - length($&);

      # Need to figure out where ((..)) ends.
      matchingbrace($in);
      my $att_pos_end = pos $in;

      # Remove the __attribute__ tag.
      substr($in, $att_pos_start, $att_pos_end - $att_pos_start) = '';
  }

  # Remove arguments of functions (heuristics only): 
  # paren word comma
  # paren word space non-paren
  # start a list of arguments. (May be "cdecl *myfunc"?) XXXXX ?????
  while ( $in =~ /\(\s*\w+(,|\s+[^\)\s])/g ) {
    pos $in = $start = pos($in) - length($&) + 1; # Cannot use $` because of optimizations
    matchingbrace($in);
    substr ($in, $start, pos($in) - 1 - $start) = '';
  } 
  # Remove array specifiers
  $in =~ s/\[[\w\s]*\]/ /g;
  # Several words in a row cannot be new typedefs, but the last one.
  $in =~ s/(\w+\s+)+(?=[^\s,;\[\{\)])//g;
  ( $in =~ /(\w+)/g );
}

sub matchingbrace {
  # pos($_[0]) is after the opening brace now
  my $n = 0;
  while ($_[0] =~ /([\{\[\(])|([\]\)\}])/g) {
    $1 ? $n++ : $n-- ;
    return 1 if $n < 0;
  }
  # pos($_[0]) is after the closing brace now
  return;				# false
}

sub remove_Comments_no_Strings { # We expect that no strings are around
    my $in = shift;
    $in =~ s,/(/.*|\*[\s\S]*?\*/),,g ; # C and C++
    die "Unfinished comment" if $in =~ m,/\*, ;
    $in;
}

sub sanitize {		# We expect that no strings are around
    my $in = shift;
    # C and C++, strings and characters
    $in =~ s{ / ( 
		 / .*			# C++ style
		 |
		 \* [\s\S]*? \*/	# C style
		)			# (1)
		| '([^\\\']|\\.)+'	# (2) Character constants
		  | "([^\\\"]|\\.)*"	# (3) Strings
		    | ( ^ \s* \# .* 	# (4) Preprocessor
			( \\ $ .* )* )	# and continuation lines
	    } {
	      # We want to preserve the length, so that one may go back
	      defined $1 ? ' ' x length $1 :
		defined $4 ? ' ' x length $4 :
		  defined $2 ? "'" . ' ' x length($2) . "'" :
		    defined $3 ? '"' . ' ' x length($3) . '"' : '???'
	    }xgem ;
    die "Unfinished comment" if $in =~ m{ /\* }x;
    $in;
}

sub top_level {			# We expect argument is sanitized
  # Note that this may remove the variable in declaration: int (*func)();
  my $in = shift;
  my $start;
  my $out = $in;
  while ($in =~ /[\[\{\(]/g ) {
    $start = pos $in;
    matchingbrace($in);
    substr($out, $start, pos($in) - 1 - $start) 
      = ' ' x (pos($in) - 1 - $start);
  }
  $out;
}

sub remove_type_decl {		# We suppose that the arg is top-level only.
  my $in = shift;
  $in =~ s/(\btypedef\b.*?;)/' ' x length $1/gse;
  # The following form may appear only in the declaration of the type itself:
  $in =~ 
    s/(\b(enum|struct|union|class)\b[\s\w]*\{\s*\}\s*;)/' ' x length $1/gse;
  $in;
}

sub new { 
  my $class = shift; 
  my $out = SUPER::new $class $recipes;  
  $out->set(@_); 
  $out;
}

sub do_declarations {
  my @d = map do_declaration($_, $_[1], $_[2]), @{ $_[0] };
  \@d;
}

# Forth argument: if defined, there maybe no identifier. Generate one
# basing on this argument.

sub do_declaration {
  my ($decl, $typedefs, $keywords, $argnum) = @_;
  $decl =~ s/;?\s*$//;
  my ($type, $typepre, $typepost, $ident, $args, $w, $pos, $repeater);
  $decl =~ s/^\s*extern\b\s*//;
  $pos = 0;
  while ($decl =~ /(\w+)/g and ($typedefs->{$1} or $keywords->{$1})) {
    $w = $1;
    if ($w =~ /^(struct|class|enum|union)$/) {
      $decl =~ /\G\s+\w+/g or die "`$w' is not followed by word in `$decl'";
    }
    $pos = pos $decl;
  }
  pos $decl = $pos;
  $decl =~ /\G[\s*]*\*/g or pos $decl = $pos;
  $type = substr $decl, 0, pos $decl;
  $decl =~ /\G\s*/g or pos $decl = length $type; # ????
  $pos = pos $decl;
  if (defined $argnum) {
    if ($decl =~ /\G(\w+)((\s*\[[^][]*\])*)/g) { # The best we can do with [2]
      $ident = $1;
      $repeater = $2;
      $pos = pos $decl;
    } else {
      pos $decl = $pos = length $decl;
      $type = $decl;
      $ident = "arg$argnum";
    }
  } else {
    die "Cannot process declaration `$decl' without an identifier" 
      unless $decl =~ /\G(\w+)/g;
    $ident = $1;
    $pos = pos $decl;
  }
  $decl =~ /\G\s*/g or pos $decl = $pos;
  $pos = pos $decl;
  if (pos $decl != length $decl) {
    pos $decl = $pos;
    die "Expecting parenth after identifier in `$decl'\nafter `",
      substr($decl, 0, $pos), "'"
      unless $decl =~ /\G\(/g;
    my $argstring = substr($decl, pos($decl) - length $decl);
    matchingbrace($argstring) or die "Cannot find matching parenth in `$decl'";
    $argstring = substr($argstring, 0, pos($argstring) - 1);
    $argstring =~ s/ ^ ( \s* void )? \s* $ //x;
    $args = [];
    my @args;
    if ($argstring ne '') {
      my $top = top_level $argstring;
      my $p = 0;
      my $arg;
      while ($top =~ /,/g) {
	$arg = substr($argstring, $p, pos($top) - 1 - $p);
	$arg =~ s/^\s+|\s+$//gs;
	push @args, $arg;
	$p = pos $top;
      }
      $arg = substr $argstring, $p;
      $arg =~ s/^\s+|\s+$//gs;
      push @args, $arg;
    }
    my $i = 0;
    for (@args) {
      push @$args, do_declaration1($_, $typedefs, $keywords, $i++);
    }
  }
  [$type, $ident, $args, $decl, $repeater];
}

sub do_declaration1 {
  my ($decl, $typedefs, $keywords, $argnum) = @_;
  $decl =~ s/;?\s*$//;
  my ($type, $typepre, $typepost, $ident, $args, $w, $pos, $repeater);
  $pos = 0;
  while ($decl =~ /(\w+)/g and ($typedefs->{$1} or $keywords->{$1})) {
    $w = $1;
    if ($w =~ /^(struct|class|enum|union)$/) {
      $decl =~ /\G\s+\w+/g or die "`$w' is not followed by word in `$decl'";
    }
    $pos = pos $decl;
  }
  pos $decl = $pos;
  $decl =~ /\G[\s*]*\*/g or pos $decl = $pos;
  $type = substr $decl, 0, pos $decl;
  $decl =~ /\G\s*/g or pos $decl = length $type; # ????
  $pos = pos $decl;
  if (defined $argnum) {
    if ($decl =~ /\G(\w+)((\s*\[[^][]*\])*)/g) { # The best we can do with [2]
      $ident = $1;
      $repeater = $2;
      $pos = pos $decl;
    } else {
      pos $decl = $pos = length $decl;
      $type = $decl;
      $ident = "arg$argnum";
    }
  } else {
    die "Cannot process declaration `$decl' without an identifier" 
      unless $decl =~ /\G(\w+)/g;
    $ident = $1;
    $pos = pos $decl;
  }
  $decl =~ /\G\s*/g or pos $decl = $pos;
  $pos = pos $decl;
  if (pos $decl != length $decl) {
    pos $decl = $pos;
    die "Expecting parenth after identifier in `$decl'\nafter `",
      substr($decl, 0, $pos), "'"
      unless $decl =~ /\G\(/g;
    my $argstring = substr($decl, pos($decl) - length $decl);
    matchingbrace($argstring) or die "Cannot find matching parenth in `$decl'";
    $argstring = substr($argstring, 0, pos($argstring) - 1);
    $argstring =~ s/ ^ ( \s* void )? \s* $ //x;
    $args = [];
    my @args;
    if ($argstring ne '') {
      my $top = top_level $argstring;
      my $p = 0;
      my $arg;
      while ($top =~ /,/g) {
	$arg = substr($argstring, $p, pos($top) - 1 - $p);
	$arg =~ s/^\s+|\s+$//gs;
	push @args, $arg;
	$p = pos $top;
      }
      $arg = substr $argstring, $p;
      $arg =~ s/^\s+|\s+$//gs;
      push @args, $arg;
    }
    my $i = 0;
    for (@args) {
      push @$args, do_declaration2($_, $typedefs, $keywords, $i++);
    }
  }
  [$type, $ident, $args, $decl, $repeater];
}

############################################################

package C::Preprocessed;
use Symbol;
use File::Basename;
use Config;

sub new {
    die "usage: C::Preprocessed->new(filename[, defines[, includes[, cpp]]])" 
      if @_ < 2 or @_ > 5;
    my ($class, $filename, $Defines, $Includes, $Cpp) 
      = (shift, shift, shift, shift, shift);
    $Cpp ||= \%Config::Config;
    my $filedir = dirname $filename || '.';
    $Includes ||= [$filedir, '/usr/local/include', '.'];
    my $addincludes = "";
    $addincludes = "-I" . join(" -I", @$Includes)
      if defined $Includes and @$Includes;
    my($sym) = gensym;
    my $cmd = "echo '\#include \"$filename\"' | $Cpp->{cppstdin} $Defines $addincludes $Cpp->{cppflags} $Cpp->{cppminus} |";
    #my $cmd = "$Cpp->{cppstdin} $Defines $addincludes $Cpp->{cppflags} $Cpp->{cppminus} < $filename |";
    #my $cmd = "echo '\#include <$filename>' | $Cpp->{cppstdin} $Defines $addincludes $Cpp->{cppflags} $Cpp->{cppminus} |";

    (open($sym, $cmd) or die "Cannot open pipe from `$cmd': $!")
      and bless $sym => $class;
}

sub text {
  my $class = shift;
  my $filter = shift;
  if (defined $filter) {
    return text_only_from($class, $filter, @_);
  }
  my $stream = $class->new(@_);
  my $oh = select $stream;
  $/ = undef;
  select $oh;
  <$stream>;
}

sub text_only_from {
  my $class = shift;
  my $from = shift || die "Expecting argument in `text_only_from'";
  my $stream = $class->new(@_);
  my $on = $from eq $_[0];
  my $eqregexp = $on ? '\"\"|' : '';
  my @out;
  while (<$stream>) {
    #print;
    
    $on = /$eqregexp[\"\/]\Q$from\"/ if /^\#/;
    push @out, $_ if $on;
  }
  join '', @out;
}

sub DESTROY {
  close($_[0]) 
    or die "Cannot close pipe from `$Config::Config{cppstdin}': err $?, $!\n";
}

# Autoload methods go after __END__, and are processed by the autosplit program.
# Return to the principal package.
package C::Scan;

1;
__END__

=head1 NAME

C::Scan - scan C language files for easily recognized constructs.

=head1 SYNOPSIS

  $c = new C::Scan 'filename' => $filename, 'filename_filter' => $filter,
                   'add_cppflags' => $addflags;
  $c->set('includeDirs' => [$Config::Config{shrpdir}]);
  
  my $fdec = $c->get('parsed_fdecls');


=head1 DESCRIPTION

B<This description is I<VERY> incomplete.>

This module uses C<Data::Flow> interface, thus one uses it in the
following fashion:

  $c = new C::Scan(attr1 => $value1, attr2 => $value2);
  $c->set( attr3 => $value3 );

  $value4 = $c->get('attr4');

Attributes are depending on some other attributes. The only
I<required> attribute, i.e., the attribute which I<should> be set, is
C<filename>, which denotes which file to parse.

All other attributes are either optional, or would be calculated basing on values of required and optional attributes.

=head2 Output attributes

=over 14

=item C<includes>

Value: reference to a list of included files.

=item C<defines_args>

Value: reference to hash of macros with arguments. The values are
references to an array of length 2, the first element is a reference
to the list of arguments, the second one being the expansion.
Newlines are not unescaped, thus

  #define C(x,y) E\
                 F

will finish with C<("C" =E<gt> [ ["x", "y"], "E\nF"])>.

=item C<defines_no_args>

Value: reference to hash of macros without arguments.  Newlines are
not escaped, thus

  #define A B

will finish with C<("A" =E<gt> "B")>.

=item C<fdecls>

Value: reference to list of declarations of functions.

=item C<inlines>

Value: reference to list of definitions of functions.

=item C<parsed_fdecls>

Value: reference to list of parsed declarations of functions. 

A parsed declaration is a reference to a list of C<(rt, nm, args, ft,
mod)>. Here C<rt> is return type of a function, C<nm> is the name,
C<args> is the list of arguments, C<ft> is the full text of the
declaration, and C<mod> is the modifier (which is always C<undef>).

Each entry in the list C<args> is of the same form C<(ty, nm, args,
ft, mod)>, here C<ty> is the type of an argument, C<nm> is the name (a
generated one if missing in the declaration), C<args> is C<undef>, and
C<mod> is the string of array modifiers.

=item C<typedef_hash>

Value: a reference to a hash which contains known C<typedef>s as keys.

=item C<typedef_texts>

Value: a reference to a list which contains known expansions of
C<typedef>s.

=item C<typedefs_maybe>

Value: a reference to a list of C<typedef>ed names. (Syncronized with
C<typedef_texts>).

=item C<vdecls>

Value: a reference to a list of C<extern> variable declarations.

=back

=cut
