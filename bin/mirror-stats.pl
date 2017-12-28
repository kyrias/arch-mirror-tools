#!/usr/bin/perl
use warnings;
use strict;
use JSON;
use WWW::Mechanize;
use Data::Dumper;

my $m = WWW::Mechanize->new();

#$m->get("https://www.archlinux.org/mirrors/status/tier/1/json");
$m->get("https://www.archlinux.org/mirrors/status/json");
my $mirrors = decode_json($m->content());

my %countries = ();

for my $mirror (@{$mirrors->{urls}}) {
	$countries{$mirror->{country_code}}++;
}

my @sorted_countries = sort {$countries{$a} <=> $countries{$b}} keys %countries;

for my $key (@sorted_countries) {
	my $value = $countries{$key};
	print "$key: $value\n";
}
