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
  DelayedTriggerable
))};

my $PROJECT_ROOT = '/Users/bernard/fieldbook';

my $includedFile = `realpath $ARGV[0]`;
chomp $includedFile;

if ($includedFile =~ m/index.js$/) {
  $includedFile = dirname($includedFile);
}

$includedFile =~ s/\.js$//;

my $className = ucfirst((fileparse($includedFile, '.js'))[0]);
if ($LOWER_CASE_NAMES->{$className}) {
  $className = lcfirst($className);
}

my ($path) = $includedFile =~ m/^$PROJECT_ROOT\/(.*)$/;
print "const $className = prequire('$path');";
