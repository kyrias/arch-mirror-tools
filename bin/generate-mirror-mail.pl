#!/usr/bin/perl
use warnings;
use strict;
use File::Basename;
use JSON;
use HTTP::Cookies;
use WWW::Mechanize;
use Date::Parse;
use Date::Format;
use Text::Template;
use Try::Tiny;

use Data::Dumper;

=head1 NAME

generate-mirror-mail.pl - Generate notification mails for broken mirrors

=head1 DESCRIPTION

Run the script and pass it URLs to the archweb mirror page (e.g.
<https://www.archlinux.org/mirrors/melbourneitmirror.net/>) via STDIN. If the
mirror has a problem the script will generate an appropriate mail and run
`compose-mail-from-stdin` which should be a script that starts your favourite
mail client with the mail. The mail is currently not complete so it cannot be
sent automatically.

Missing from the mail are:

 - the recipient addresses
 - the links to the details pages of the problematic mirror URLs

=cut

# TODO: put this in a config file
my $sender = 'bluewind@xinu.at';

#$ENV{HTTPS_CA_FILE}    = '/etc/ssl/certs/ca-certificates.crt';

my %templates = (
	'out-of-sync' => {
		'subject' => '[{$mirror_name}] Arch Linux mirror out of sync',
		'template' => 'Hi,

Your mirror seems to be out of sync since {$last_sync}, could you please
investigate?

{$mirror_urls}

Thanks,
Florian
',
	},
	'connection-failed' => {
		'subject' => '[{$mirror_name}] Arch Linux mirror not accessible{$OUT = ", ".join("/", @affected_protocols) if @affected_protocols > 0;}',
		'template' => 'Hi,

We\'re having trouble connecting to your mirror{$OUT = " via ".join(", ", @affected_protocols) if @affected_protocols > 0;}, could you
please check what\'s going on?

{$mirror_urls}

Thanks,
Florian
',
	},
);

my $cookie_jar = HTTP::Cookies->new(file => dirname($0) . "/../cookie_jar", autosave => 1);
my $mech = WWW::Mechanize->new(cookie_jar => $cookie_jar);

sub send_mail {
	my $to = shift;
	my $subject = shift;
	my $body = shift;

	open my $fh, "|compose-mail-from-stdin" or die "Failed to run mailer: $!";
	print $fh "To: $to\n";
	print $fh "From: $sender\n";
	print $fh "Subject: $subject\n";
	print $fh "\n";
	print $fh "$body";
	close $fh;
}

sub send_template_mail {
	my $to = shift;
	my $subject = shift;
	my $body = shift;
	my $values = shift;

	send_mail($to, fill_template($subject, $values), fill_template($body, $values));
}

sub fill_template {
	my $template = shift;
	my $values = shift;
	my $result = Text::Template::fill_in_string($template, HASH => $values)
		or die "Failed to fill in template: $Text::Template::ERROR";

	return $result;
}

while (<STDIN>) {
	try {
		my $url = $_;
		chomp($url);
		die "Skipping non-mirror detail URL" if $url =~ m/\/[0-9]+(\/|$)/;
		die "Skipping non-mirror detail URL" if $url eq "https://www.archlinux.org/mirrors/status/";

		$mech->get($url."/json/");
		my ($mirror_name) = ($url =~ m#/([^/]+)/?$#);
		my $json = JSON::decode_json($mech->content());

		my @out_of_sync;
		my @connection_failed;

		for my $mirror (@{$json->{urls}}) {
			if ($mirror->{last_sync}) {
				my $time = str2time($mirror->{last_sync});
				if ($time < time() - 60*60*24*3) {
					push @out_of_sync, {
						time => $time,
						url => $mirror->{url},
						details_link => $mirror->{details},
					};
				}
			} else {
			#if ($mirror->{last_sync} and $mirror->{completion_pct} < 0.9 and $mirror->{completion_pct} > 0) {
				push @connection_failed, {
					url => $mirror->{url},
					details_link => $mirror->{details},
					protocol => $mirror->{protocol},
				};
			}
		}

		# extract and deduplicate sync times
		my @last_sync = keys %{{ map { ${$_}{time} => 1 } @out_of_sync }};
		my $sent_mail = 0;

		my $to = $json->{admin_email};

		if (@out_of_sync) {
			my %values = (
					last_sync => join(", ", map {time2str("%Y-%m-%d", $_)} @last_sync),
					mirror_urls => join("\n", $url, map {${$_}{details_link}} @out_of_sync),
					mirror_name => $mirror_name,
				);
			send_template_mail($to, $templates{"out-of-sync"}{"subject"}, $templates{"out-of-sync"}{"template"}, \%values);
			$sent_mail = 1;
		}

		if (@connection_failed) {
			my %values = (
					mirror_urls => join("\n", $url, map {${$_}{details_link}} @connection_failed),
					mirror_name => $mirror_name,
				);

			my @protocols = map {${$_}{protocol}} @connection_failed;
			if (scalar(@protocols) != scalar(@{$json->{urls}})) {
				$values{affected_protocols} = \@protocols;
			}

			send_template_mail($to, $templates{"connection-failed"}{"subject"}, $templates{"connection-failed"}{"template"}, \%values);
			$sent_mail = 1;
		}

		if (!$sent_mail) {
			say STDERR "No issue detected for mirror $mirror_name";
		}

	} catch {
		warn "ignoring error: $_";
	}
}
