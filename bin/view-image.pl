#!/usr/bin/perl

use strict;
use warnings;

use FindBin qw($Bin); use lib $Bin . "/perl/lib";;

use File::Spec;
use UrlOpener;

my $file = $ARGV[0];

# Bad screen sessions...
$ENV{'DISPLAY'} = ':0';

unless ( -e $file ) {
  die "File: $file does not exist!\n"
}

my $absolute_file = File::Spec->rel2abs($file);
UrlOpener::open_url("file://$absolute_file");
