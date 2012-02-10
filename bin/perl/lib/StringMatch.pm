package StringMatch;

use base qw(Exporter);
@EXPORT_OK = qw(match_strings);  # symbols to export on request

# use warn for debugging here due to interaction with backticks in shell
# function
sub match_strings {
  my $string    = shift;
  my $set       = shift;
  my $verbose   = shift;
  my $id_string = shift;

  my $hash = { map { $_ => 1 } @$set };

  # First exact matches
  if ( exists $hash->{$string} ) {
    warn "$id_string: Exact match $string\n" if ( $verbose );
    return $string;
  }

  my $matches;
  $matches = grep_match(qr(^\Q$string\E), $set, "$id_string: Prefix", $verbose);
  return $matches->[0] if ( scalar @$matches == 1 );

  $matches = grep_match(qr(\Q$string\E), $set, "$id_string: Search", $verbose);
  return $matches->[0] if ( scalar @$matches == 1 );

  $matches = grep_match(qr($string), $set, "$id_string: Regex", $verbose);
  return $matches->[0] if ( scalar @$matches == 1 );

  die "Unable to find a match for $string";
}

sub grep_match {
  my $pattern = shift;
  my $array   = shift;
  my $type    = shift;
  my $verbose = shift;

  my @results = grep { $_ =~ $pattern } @$array;

  if ( scalar @results == 1 ) {
    my $match = $results[0];
    warn "$type match: $match\n" if ( $verbose );
  }
  elsif ( scalar @results > 1 ) {
    if ( $verbose ) {
      warn "Possible $type matches:\n";
      foreach my $match (@results) {
        warn "  $match\n";
      }
    }
  }
  else {
    warn "No matches for $type\n" if ( $verbose );
  }

  return \@results;
}

1;
