#!/usr/bin/env perl
#
# hgk.pl - Hatena Group Keyword Writer.
#
# Copyright (C) 2009 by Hiroshige Umino.
# <yaotti@gmail.com>
#
# Special thanks to:
# - Hiroshi Yuki http://www.hyuki.com/techinfo/hatena_diary_writer.html
#
# This program is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.
#
use strict;
my $VERSION = "0.1";

use warnings;
use DateTime;
use Digest::MD5 qw(md5_base64);
use File::Basename;
use Getopt::Long;
use HTTP::Request::Common;
use HTTP::Cookies;
use IO::File;
use LWP::UserAgent;
use Perl6::Say;

my $user_agent;
my ( $filename, $keyword );
my ( $username, $password, $groupname );
my $hatena_url             = 'http://g.hatena.ne.jp';
my $keyword_url            = '';
my $hatena_sslregister_url = 'https://www.hatena.ne.jp/login';
my $option_ok;
my $cookie_file = '.cookie';
my $cookie_jar;
my $rkm;
my ( $debug, $cookie );

# Crypt::SSLeay check.
eval { require Crypt::SSLeay; };
if ($@) {
    print_message(
        "WARNING: Crypt::SSLeay is not found, use non-encrypted HTTP mode.");
    $hatena_sslregister_url = 'http://www.hatena.ne.jp/login';
}

sub bootstrap {
    my ($file) = @_;
    unless ( defined $groupname ) {
        print 'Group name: ';
        chomp( $groupname = <STDIN> );
    }
    $keyword_url = sprintf 'http://%s.g.hatena.ne.jp/keyword', $groupname;

    $filename = basename($file);
    $filename =~ /(.*).txt/ or die "input file must be a txt one: $filename";
    $keyword = $1;
    1;
}

sub login {
    $user_agent = LWP::UserAgent->new;
    $user_agent->env_proxy;
    unless ( defined $username ) {
        print 'Username: ';
        chomp( $username = <STDIN> );
    }

    if ( $cookie and -e ($cookie_file) ) {
        say_debug("login: Loading cookie jar.");
        $cookie_jar = HTTP::Cookies->new;
        $cookie_jar->load($cookie_file);
        $cookie_jar->scan( \&get_rkm );
        say_debug( "login: \$cookie_jar = " . $cookie_jar->as_string );
        say "Skip login.";
        return;
    }

    unless ( defined $password ) {
        print 'Password: ';
        chomp( $password = <STDIN> );
    }
    my $form = {
        name     => $username,
        password => $password,
        mode     => 'enter',
        backurl  => $keyword_url,
    };
    if ($cookie) {
        $form->{persistent} = "1";
    }

    say("Login to $hatena_url as $form->{name}.");

    my $r = $user_agent->simple_request(
        HTTP::Request::Common::POST( "$hatena_sslregister_url", $form ) );
    say "login: " . $r->status_line;
    say_debug( "login: \$r = " . $r->content );
    if (not $r->is_redirect and not $r->is_success) {
        error_exit("Login: Unexpected response: ", $r->status_line);
    }
    say "Login OK.";
    say_debug("login: Making cookie jar.");

    $cookie_jar = HTTP::Cookies->new;
    $cookie_jar->extract_cookies($r);
    $cookie_jar->save($cookie_file);
    $cookie_jar->scan( \&get_rkm );

    say_debug( "login: \$cookie_jar = " . $cookie_jar->as_string );
}

sub get_timestamp {
    my $dt = DateTime->now( time_zone => 'Asia/Tokyo' );
    $dt->strftime("%Y%m%d%H%M%S");
}

sub get_rkm {
    my ( $version, $key, $val ) = @_;
    if ( $key eq 'rk' ) {
        $rkm = md5_base64($val);
        say_debug( "get_rkm: \$rkm = " . $rkm );
    }
}

sub update_group_keyword {
    my $body;
    say_debug("update_group_keyword: $groupname, $keyword");
    my $fh = new IO::File $filename, 'r' or die "can't open file";
    $body = join '', <$fh>;
    $user_agent->cookie_jar($cookie_jar);
    my $r = $user_agent->simple_request(
        HTTP::Request::Common::POST(
            $keyword_url,
            Content_Type => 'form-data',
            Content      => [
                mode       => 'enter',
                rkm        => $rkm,
                word       => $keyword,
                timestamp  => get_timestamp,
                olddelflag => '0',
                body       => $body,
            ]
        )
    );
    say_debug( "post_it: " . $r->status_line );
    if ( not $r->is_redirect ) {
        error_exit( "Post: Unexpected response: ", $r->status_line );
    }

    # Check the result. OK if the location ends with the date.
    if ( $r->header("Location") =~ m{\Q$keyword\E} ) {
        say_debug("post_it: returns 1 (OK).");
        return 1;
    } else {
        say_debug("post_it: returns 0 (ERROR).");
        return 0;
    }

}

sub logout {
    return unless $user_agent;
    if ( $cookie and -e ($cookie_file) ) {
        say "Skip logout.";
        return;
    }

    my $form;
    $form->{name}     = $username;
    $form->{password} = $password;

    say "Logout from $hatena_url as $form->{name}.";
    $user_agent->cookie_jar($cookie_jar);
    my $r = $user_agent->get("$hatena_url/logout");
    say_debug( "logout: " . $r->status_line );

    if ( not $r->is_redirect and not $r->is_success ) {
        error_exit( "Logout: Unexpected response: ", $r->status_line );
    }
    unlink($cookie_file);
    say "Logout OK.";
}

sub say_debug {
    if ($debug) {
        say "DEBUG: ", @_;
    }
}

sub error_exit(@) {
    say "ERROR: ", @_;
    unlink($cookie_file);
    exit(1);
}

sub HELP_MESSAGE {
    print <<"EOD";

Usage: perl $0 [Options] KEYWORD.txt

Options:
    --version       Show version.
    --help          Show this message.
    -d, --debug     Debug. Use this switch for verbose log.
    -u username     Username. Specify username.
    -p password     Password. Specify password.
    -g groupname    Groupname. Specify groupname for keyword.
    -c, --cookie    Cookie. Skip login/logout if $cookie_file exists.

EOD
    exit(0);
}

sub VERSION_MESSAGE {
    print <<"EOD";
Hatena Group Keyword Writer Version $VERSION
Copyright (C) 2009 by Hiroshige Umino.
EOD
    exit(0);
}

sub main {
    $option_ok = GetOptions(
        'group=s'    => \$groupname,
        'user=s'     => \$username,
        'password=s' => \$password,
        'debug'      => \$debug,
        'cookie'     => \$cookie,
        'help'       => \&HELP_MESSAGE,
        'version'    => \&VERSION_MESSAGE,
    );
    bootstrap(@ARGV);
    login;
    update_group_keyword;
    logout;
}

main();

__END__
