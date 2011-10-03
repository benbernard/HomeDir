package Amling::Git::GRD::Utils;

use strict;
use warnings;

use Amling::Git::Utils;

sub run_shell
{
    my $first_shell = shift;
    my $allow_index = shift;
    my $allow_wtree = shift;

    my $shell = $ENV{'SHELL'} || '/bin/sh';
    my $grd_level = ($ENV{'GRD_LEVEL'} || 0);

    EDITLOOP:
    while(1)
    {
        if($first_shell)
        {
            {
                local $ENV{'GRD_LEVEL'} = ($grd_level + 1);
                print "GRD level: " . ($grd_level + 1) . "\n";
                system($shell);
            }
        }
        else
        {
            $first_shell = 1;
        }

        my $fail;
        my ($dirtyness, $message) = Amling::Git::Utils::get_dirtyness();
        if(!$allow_index && $dirtyness >= 1)
        {
            $fail = $message;
        }
        if(!$allow_wtree && $dirtyness >= 2)
        {
            $fail = $message;
        }

        if(!$fail)
        {
            return;
        }

        # TODO: extract menu util
        while(1)
        {
            print "$fail\n";
            print "What should I do?\n";
            print "s - run a shell\n";
            print "q - abort entire rebase\n";
            print "> ";
            my $ans = <>;
            chomp $ans;

            if($ans eq "q")
            {
                print "Giving up.\n";
                exit 1;
            }
            if($ans eq "s")
            {
                next EDITLOOP;
            }

            print "Not an option: $ans\n";
        }
    }
}

sub run
{
    my @cmd = @_;

    print "Running: " . join(", ", @cmd) . "...\n";

    return (system(@cmd) == 0);
}

sub escape_msg
{
    my $msg = shift;

    $msg =~ s/\\/\\\\/g;
    $msg =~ s/\n/\\n/g;

    return $msg;
}

sub unescape_msg
{
    my $msg = shift;

    $msg =~ s/\\n/\n/g;
    $msg =~ s/\\\\/\\/g;

    return $msg;
}

1;
