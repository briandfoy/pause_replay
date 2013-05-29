#!/Users/brian/bin/perls/perl5.14.2
use v5.10.1;
use utf8;
use strict;
use warnings;
no warnings 'uninitialized';

use Date::Parse qw(str2time);
use Email::Simple;
use File::Spec::Functions;

my $dir = './perl.modules';
opendir my $dh, $dir or die "Could not open perl.modules! $!\n";

my %date;
my %Seen;
my %From;
my $files;

my %PAUSE = map { lc $_, 1 } qw(
	upload@pause.perl.org
	upload@p11.speed-link.de
	upload@pause.x.perl.org
	);

my %Regexes = (
	mailing_list_added  => [ qr/Mailing list added to PAUSE database/, \&null ],
	mailing_list_update => [ qr/Mailinglist update for (.*)/,          \&null ],
	module_updated      => [ qr/Module (.*) updated/,                  \&null ],
	module_submissiom   => [ qr/Module submission (.*)/,               \&null ],
	module_update       => [ qr/Module update for (.*)/,               \&null ],
	new_module          => [ qr/New module (.*)/,                      \&null ],
	pause_id_request    => [ qr/PAUSE ID request \((.*?); (.*?)\)/,    \&null ],
	uri_update          => [ qr/Uri update for (.*)/,                  \&null ],
	user_update         => [ qr/User update for (.*)/,                 \&null ],
	welcome_new_user    => [ qr/Welcome new user (.*)/,                \&welcome_new_user ],
	);

open my $nulls,    '>', 'null_emails.txt';
open my $froms,    '>', 'from_emails.txt';
open my $subjects, '>', 'subjects.txt';

my $count;
FILE: while( my $file = readdir( $dh ) ) {
	next if( $file eq '.' or $file eq '..' );
	$files++;
	my $text = do { local( @ARGV, $/ ) = catfile( $dir, $file ); <> };
	next unless length $text;
	my $email = eval { Email::Simple->new( $text ) } or next;

	my $from = $email->header( 'From' );
	my( $address, $name ) = split /\s+/, $from, 2;
	$From{$address}++;

	say { $froms }  "$file -> $from";
	say { $nulls } $file unless length $address;

	next unless exists $PAUSE{ $address };

	my $subject = $email->header( 'Subject' );
	say { $subjects } $subject;

	my $date_s = $email->header( 'Date' );
	my $epoch = str2time( $date_s );

	my $found = 0;
	REGEX: foreach my $key ( keys %Regexes ) {
		my $regex = $Regexes{$key}[0];
		next unless $subject =~ m/$regex/;
		my $data = $Regexes{$key}[1]($email);

		$data->{type}    = $key;
		$data->{epoch}   = $epoch;
		$data->{subject} = $subject;
		$data->{file}    = $file;

		say Dumper( $data ); use Data::Dumper;
		$found = 1;
		last REGEX;
		}

	last if $count++ > 10;	
	warn "Could not match PAUSE message in $file\n" unless $found;
#	my $body = $email->body;
	}

sub null {
	}

sub welcome_new_user {
	my( $email ) = @_;

	my %captures = $email->body =~ m/
		(userid) \h for \h you: \R+
		\h+ (\S+)
		.*
		\R 
		\h+ (Name):      \h+      (.*?) \R
		\h+ (email):     \h+      (.*?) \R
		\h+ (homepage):  \h+      (.*?) \R
		\h+ (enteredby): \h+      (.*?) \R
		/xsi or warn "Did not match!";

	\%captures;
	}

__END__
42576 upload@pause.perl.org ("Perl Authors Upload Server")
 7871 upload@p11.speed-link.de ("Perl Authors Upload Server")
 3046 
 2615 upload@pause.x.perl.org ("Perl Authors Upload Server")


Mailing list added to PAUSE database
Mailinglist update for (.*)
Module (.*) updated
Module submission (.*)
Module update for (.*)
New module (.*)
PAUSE ID request (%s; %s)
Uri update for (.*)
User update for (.*)
Welcome new user (.*)
