#!/usr/bin/perl -w

use strict;
use warnings;

$| = 1;

$ENV{'DISPLAY'} = ':0';

my @selection = `xclip -o`;
open(my $cmdh, '|-', 'xclip', '-i') or die "could not run xclip: $!";
print $cmdh join(' ', map { chomp $_; $_ } @selection);
close $cmdh;

system('ratpoison', '-c', 'echo joined lines');
