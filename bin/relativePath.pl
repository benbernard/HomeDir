#!/usr/bin/perl -w

use strict;
use File::Spec;
use File::Basename qw(fileparse dirname);

my $LOWER_CASE_NAMES = {map {$_ => 1} (qw(
  Strings
  Values
  Main
  Heroku
  Errors
  Env
  MemoryManagement
  EventbriteHelpers
  Helpers
  Mailer
  Constants
  Domains
  GlobalEvents
  ApiJwtToken
  Metrics
  Urls
))};

my $PROJECT_ROOT = '/Users/bernard/fieldbook';

my $includedFile = $ARGV[0];
my $sourceFile = $ARGV[1];

if ($includedFile =~ m/index.js$/) {
  $includedFile = dirname($includedFile);
}

$includedFile =~ s/\.js$//;

my $className = ucfirst((fileparse($includedFile, '.js'))[0]);
if ($LOWER_CASE_NAMES->{$className}) {
  $className = lcfirst($className);
}

my ($path) = $includedFile =~ m/^$PROJECT_ROOT\/(.*)$/;
print "var $className = prequire('$path');";

# if ($sourceFile =~ m/^$PROJECT_ROOT\/(server|test|scripts)/ ) {
#   my ($path) = $includedFile =~ m/^$PROJECT_ROOT\/(.*)$/;
#   print "var $className = prequire('$path');";
#   exit 0;
# }

# my $base = dirname($sourceFile);

# my $path = File::Spec->abs2rel($includedFile, $base);

# if (!($path =~ m/^\./)) {
#   $path = "./$path";
# }

# print "var $className = require('$path');"
