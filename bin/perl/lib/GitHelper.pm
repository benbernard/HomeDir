use strict;
use warnings;

package GitHelper;

use IPC::Open3 qw(open3);
use POSIX qw(getpwuid);

use base 'Exporter';
our @EXPORT_OK = qw(run_git get_config get_config_with_default get_config_default_boolean has_remote has_branch run_hub);

our $DEBUG=0;

sub run_git {
    return run_command('git', @_)
}

sub run_command {
    my @command = @_;

    my $command_str = join(" ", @command);
    print "Running $command_str\n" if $DEBUG;

    my ($wh, $rh, $errh);
    my $pid = open3($wh, $rh, $errh, @command) or die "Could not run git command: $command_str: $!";
    waitpid($pid, 0);
    my $exit_code = $?;

    local $/;
    my $output = <$rh>;

    print "$output" if $DEBUG;

    if ($exit_code) {
        die "Failed running command! $command_str\nOutput: $output"
    }
    return $output;
}

sub get_config {
    my $name = shift;

    open(my $handle, '-|', 'git', 'config', '--get', $name) or die "Could not run git config: $!";
    local $/;
    my $value = <$handle>;
    close $handle;

    return $value;
}

sub set_config {
    my $name = shift;
    my $value = shift;

    run_git('config', $name, $value)
}

sub get_config_with_default {
    my $name = shift;
    my $value = shift;
    my $default = shift;

    return $value if defined $value;

    my $from_config = get_config($name);
    return $from_config if $from_config;

    return $default;
}

sub get_config_default_boolean {
    my $raw_result = get_config_with_default(@_);

    if ($raw_result =~ m/^[Ff]alse$/) {
        return 0;
    }

    if ($raw_result =~ m/^[Nn]o$/) {
        return 0;
    }

    return $raw_result;
}

sub has_remote {
    my $name = shift;

    eval { 
        run_git('remote', 'show', '-n', $name);
    };

    my $error = $@;
    undef $@;
    return not $error;
}

sub has_branch {
    my $name = shift;

    eval { 
        run_git('show', $name)
    };

    my $error = $@;
    undef $@;
    return not $error;
}

sub run_hub {
    ensure_hub_config();
    open_tunnel();
    my $output = run_command('hub', @_);
}

{
    my $has_run = 0;
    sub ensure_hub_config {
        if (not $has_run) {
            set_config('hub.host', 'HOST_HERE');
            set_config('hub.protocol', 'https');
        }
        $has_run = 1;
    }
}

{
    my $tunnel_is_up = 0;

    sub needs_tunnel {
        if(run_command('curl', 'https://HOST_HERE') =~ m/gdwall/) {
            return 1;
        }
        return 0;
    }

    sub open_tunnel {
        return if (!needs_tunnel());
        return if ($tunnel_is_up);

        print "Github connection needs an ssh tunnel.  I'm going to set it up, it may require sudo credentials\n";
        close_tunnel(1);

        my $user = (getpwuid($<))[0];
        system("sudo ssh -f -N -L443:HOST_HERE:443 -i ~/.ssh/id_rsa $user\@BASTION_HERE");
        run_command("sudo cp /etc/hosts /etc/hosts.orig");
        run_command("sudo sh -c 'echo 127.0.0.1	HOST_HERE >> /etc/hosts'");
    }

    sub close_tunnel {
        my $force = shift;
        return if (!$force && !$tunnel_is_up);
        run_command("ps -ef | grep 'ssh.*HOST_HERE:443' | grep -v grep | awk '{print \$2}' | sudo xargs kill -9");
        if ( -e '/etc/hosts.orig' ) {
            run_command("sudo cp /etc/hosts.orig /etc/hosts");
            run_command("sudo rm /etc/hosts.orig");
        }
        $tunnel_is_up = 0;
    }
}

END {
    close_tunnel()
}

1;
