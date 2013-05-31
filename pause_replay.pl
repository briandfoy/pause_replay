#!/Users/brian/bin/perls/perl5.14.2
use v5.14;
use utf8;
use strict;
use warnings;
no warnings 'uninitialized';

use Date::Parse qw(str2time);
use Email::Simple;
use File::Spec::Functions;
use JSON::XS qw(encode_json);

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
	module_updated      => [ qr/Module (.*) updated/,                  \&module_updated ],
	module_submission   => [ qr/Module submission (.*)/,               \&module_submission ],
	module_update       => [ qr/Module update for (.*)/,               \&module_update ],
	new_module          => [ qr/New module (.*)/,                      \&null ],
	pause_id_request    => [ qr/PAUSE ID request \((.*?); (.*?)\)/,    \&pause_id_request ],
	uri_update          => [ qr/Uri update for (.*)/,                  \&null ],
	user_update         => [ qr/User update for (.*)/,                 \&user_update ],
	welcome_new_user    => [ qr/Welcome new user (.*)/,                \&welcome_new_user ],
	);

open my $nulls,    '>', 'null_emails.txt';
open my $froms,    '>', 'from_emails.txt';
open my $subjects, '>', 'subjects.txt';

my $coder = JSON::XS->new->pretty;

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
	say { $subjects } "$file -> $subject";

	my $date_s = $email->header( 'Date' );
	my $epoch = str2time( $date_s );

	my $message_id = $email->header( 'Message-ID' ) =~ s/[><]//gr;

	my $found = 0;
	REGEX: foreach my $key ( keys %Regexes ) {
		my $regex = $Regexes{$key}[0];
		next unless $subject =~ m/$regex/;
		
		my %grand;
		my $data = $Regexes{$key}[1]($email);
		
		unless( defined $data ) {
			warn "$key subroutine returned undefined for $file\n";
			next FILE;			
			}

		my %meta = (
			type       => $key,
			epoch      => $epoch,
			subject    => $subject,
			file       => $file,
			message_id => $message_id,
			from       => $address,
			);
		$grand{meta} = \%meta;
		$grand{data} = $data;
		
		my $json_data = $coder->encode( \%grand );
		my $json_file = $file =~ s/\.txt\Z/.json/r;
		my $json_path = catfile( 'json', $json_file );
		open my $jfh, '>:utf8', $json_path or
			warn "Could not open $json_path: $!\n";
		print { $jfh } $json_data;

		$found = 1;
		last REGEX;
		}

	last if $count++ > 10000;	
	warn "Could not match PAUSE message in $file\n" unless $found;
#	my $body = $email->body;
	}

sub null { return }

sub mailing_list_added {
	my( $email ) = @_;

	}


sub mailing_list_update{
	my( $email ) = @_;

	}


sub module_updated     {
	my( $email ) = @_;

=pod
Record update in the PAUSE database, table "mods":

       modid: [Authen::Krb5]
       statd: [R] was [c]
       stats: [d]
       statl: [c]
       stati: [O]
 description: [Interface to Kerberos 5 API] was [Interface to Kerberos API]
      userid: [JHORWITZ]
   chapterid: [14]

Data entered by Andreas Kˆnig (ANDK).
Please check if they are correct.
=cut

	}


sub module_submission  {
	my( $email ) = @_;

	my $body = $email->body;

	open my $fh, '<', \$body;

	my %data;
	my $start = 0;
	while( <$fh> ) {
		if( ! $start && m/\AThe following module/ ) { $start = 1 }
		next unless $start;
		next if /\A\s+\Z/;
	
		s/\A\s+//;
	
		if( my @captures = m/\A (\S+): \h+ (.*)/x ) {		
			$data{$captures[0]} = $captures[1];
			}
		}

	foreach my $key ( qw(userid enteredby chapterid) ) {
		my( @ids ) = $data{$key} =~ m/\A (\S+) \h+ \( (.*?) \)/x;
		delete $data{$key};
		$data{$key}{id}   = $ids[0];
		$data{$key}{name} = $ids[1];
		}

	my @pairs = (
		[ qw(communities similar) ],
		[ qw(similar rationale)   ],
		[ qw(rationale enteredby) ],
		);

	foreach my $pair ( @pairs ) {
		if( $body =~ m/(\Q$$pair[0]\E): \s+ (.*) (?:\R\h+\Q$$pair[1]\E:)/xis ) {
			my( $key, $value ) = ( $1, $2 );
			chomp $value;
			$data{$key} = $value;
			}
		}
		
	return \%data;
	}


sub module_update {
	my( $email ) = @_;

	my $body = $email->body;

	open my $fh, '<', \$body;
	
	my %data;
	my $start = 0;
	while( <$fh> ) {
		if( ! $start && m/\ARecord update/ ) { $start = 1 }
		next unless $start;
		next if /\A\s+\Z/;
		
		s/\A\s+//;
		
		if( my @captures = m/\A (\S+): \h+ \[ (.*?) \] (?: \h+ was \h+ \[ (.*?) \] )?/x ) {		
			$data{$captures[0]}{was} = $captures[1];
			$data{$captures[0]}{changed_to} = $captures[2] if defined $captures[2];
			}
			
		if( m/Data entered by (\S+) \((.*?)\)/ ) {
			$data{entered_by}{id} = $1;
			$data{entered_by}{name} = $2;
			}
		}

	\%data;
	}


sub new_module         {
	my( $email ) = @_;

	}


sub pause_id_request   {
	my( $email ) = @_;

	my %captures = $email->body =~ m/
		Request \h+ to \h+ register \h+ new \h+ user
		\s*
		\R
		\h+ (fullname):   \h+      (.*?) \R
		\h+ (userid):     \h+      (.*?) \R
		\h+ (mail):       \h+      (.*?) \R
		\h+ (homepage):   \h+      (.*?) \R 
		\h+ (why):
		\s+ (.*?) \s+
		The \h+ following \h+ links
		/xsi or warn "Did not match pause_id_request!\n";

	\%captures;
	}


sub uri_update         {
	my( $email ) = @_;

	}


sub user_update {
	my( $email ) = @_;

	my $body = $email->body;

	open my $fh, '<', \$body;
	
	my %data;
	my $start = 0;
	while( <$fh> ) {
		if( ! $start && m/\ARecord update/ ) { $start = 1 }
		next unless $start;
		next if /\A\s+\Z/;
		
		s/\A\s+//;
		
		if( my @captures = m/\A (\S+): \h+ \[ (.*?) \] (?: \h+ was \h+ \[ (.*?) \] )?/x ) {		
			$data{$captures[0]}{was} = $captures[1];
			$data{$captures[0]}{changed_to} = $captures[2] if defined $captures[2];
			}
			
		if( m/Data were entered by (\S+) \((.*?)\)/ ) {
			$data{entered_by}{id} = $1;
			$data{entered_by}{name} = $2;
			}
		}

	\%data;
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
		/xsi or warn "Did not match welcome_new_user!\n";

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
