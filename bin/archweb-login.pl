#!/usr/bin/perl

use warnings;
use strict;

use File::Basename;
use Config::Tiny;
use WWW::Mechanize;
use HTTP::Cookies;

my $Config = Config::Tiny->new();
$Config = Config::Tiny->read(dirname($0) . "/../settings.conf");

my $cookie_jar = HTTP::Cookies->new(file => dirname($0) . "/../cookie_jar", autosave => 1);
my $mech = WWW::Mechanize->new(agent => "arch-mirror-tools", cookie_jar => $cookie_jar);

$mech->get("https://www.archlinux.org/login/");
my $res = $mech->submit_form(
	form_id => "dev-login-form",
	fields => {
		username => $Config->{account}->{username},
		password => $Config->{account}->{password}
	}
);
