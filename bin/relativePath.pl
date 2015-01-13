#!/usr/bin/perl -w

use strict;
use File::Spec;
use File::Basename qw(fileparse);

my $file = $ARGV[0];
my $base = $ARGV[1];

my $path = File::Spec->abs2rel($file, $base);
my $basename = ucfirst((fileparse($file, '.js'))[0]);

print "var $basename = require('$path');\n"
