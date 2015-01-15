#!/usr/bin/perl -w

use strict;
use File::Spec;
use File::Basename qw(fileparse dirname);

my $file = $ARGV[0];
my $base = dirname($ARGV[1]);

my $path = File::Spec->abs2rel($file, $base);

if (!($path =~ m/^\./)) {
  $path = "./$path";
}

my $basename = ucfirst((fileparse($file, '.js'))[0]);

print "var $basename = require('$path');"
