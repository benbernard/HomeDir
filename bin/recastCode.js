#!/usr/bin/perl

use strict;

# Slurp in everything
undef $/;
my $code = <>;

my $position = index $code, 'function';

if ($position == (index $code, 'function *')) {
  $code =~ s/function \*/function/;
  $code =~ s/.async\(\)//;
} else {
  $code =~ s/function \(/function * \(/;
  $code =~ s/}$/}.async()/;
}

print $code;
print $code;
