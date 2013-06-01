#!/Users/brian/bin/perls/perl5.14.2
use v5.14;
use utf8;
use strict;
use warnings;
no warnings 'uninitialized';

use Date::Parse qw(str2time);
use Email::Simple;
use Encode;
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
	mailing_list_added  => [ qr/Mailing list added to PAUSE database/, \&mailing_list_added ],
	mailing_list_update => [ qr/Mailinglist update for (.*)/,          \&mailing_list_update ],
	module_updated      => [ qr/Module (.*) updated/,                  \&module_updated ],
	module_submission   => [ qr/Module submission (.*)/,               \&module_submission ],
	module_update       => [ qr/Module update for (.*)/,               \&module_update ],
	new_module          => [ qr/New module (.*)/,                      \&new_module ],
	pause_id_request    => [ qr/PAUSE ID request/,                     \&pause_id_request ],
	uri_update          => [ qr/Uri update for (.*)/,                  \&uri_update ],
	user_update         => [ qr/User update for (.*)/,                 \&user_update ],
	welcome_new_user    => [ qr/Welcome new user (.*)/,                \&welcome_new_user ],
	);

# some files have the wrong encodings
my %Encoding_overrides = (
	'12007.txt' => 'UTF-8'
	);

open my $nulls,    '>', 'null_emails.txt';
open my $froms,    '>', 'from_emails.txt';
open my $subjects, '>', 'subjects.txt';
open my $errors,   '>', 'errors.txt';

my $coder = JSON::XS->new->pretty;

my $count;
FILE: while( my $file = readdir( $dh ) ) {
	next if( $file eq '.' or $file eq '..' );
	$files++;
	my $text = do { 
		local $/;
		my $file = catfile( $dir, $file ); 
		
		open my $fh, '<:raw', $file;
		<$fh>
		};
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

	my $content_type = $email->header( 'Content-type' );
	my( $encoding ) = $content_type =~ /Charset\s*=\s*(\S+)/;
	
	$encoding = $Encoding_overrides{$file} 
		if exists $Encoding_overrides{$file};

	if( $encoding ) {
		my $enc_object = find_encoding( $encoding );
		my $body = decode( $enc_object, $email->body );
		$email->body_set( $body );
		}

	my $found = 0;
	REGEX: foreach my $key ( keys %Regexes ) {
		my $regex = $Regexes{$key}[0];
		next unless $subject =~ m/$regex/;
		
		my %grand;
		my $data = $Regexes{$key}[1]($email);
		
		unless( defined $data ) {
			warn "$key subroutine returned undefined for $file\n";
			say { $errors } "$file -> $subject -> $key";
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
	}

sub null { return }


sub mailing_list_added {
	my( $email ) = @_;

	my %captures = $email->body =~ m/
		Mailing \h+ list \h+ (entered \h+ by) \h+ (.*?):
		\s*
		\R
		\h* (Userid):       \h*      (.*?) \R
		\h* (Name):         \h*      (.*?) \R
		\h* (Description):  \h*      (.*?) \R
		/xsi or do{ warn "Did not match mailing_list_added!\n"; return };

	\%captures;

=pod

Mailing list entered by Andreas Kˆnig:

Userid:      RISCOSML
Name:        The Risc-OS perl porters mailing list
Description:  


Mailing list entered by Kurt D. Starsinic:

Userid:      CAIDA
Name:        CAIDA team
Description: This is a closed list.

=cut

	}


sub mailing_list_update{
	my( $email ) = @_;

	my $body = $email->body;

	open my $fh, '<:utf8', \$body;
	
	my %data;
	my $start = 0;
	while( <$fh> ) {
		if( ! $start && m/\ARecord update in the PAUSE mailinglists database/ ) { $start = 1 }
		next unless $start;
		next if /\A\s+\Z/;
		
		s/\A\s+//;
		
		if( my @captures = m/\A (\S+): \h+ \[ (.*?) \] (?: \h+ was \h+ \[ (.*?) \] )?/x ) {		
			$data{$captures[0]}{was} = $captures[1];
			$data{$captures[0]}{changed_to} = $captures[2] if defined $captures[2];
			}
			
		if( m/Data entered by\s+(.*?)\./ ) {
			$data{entered_by}{id} = $2;
			$data{entered_by}{name} = $1;
			}
		}

	warn "Problem with mailing_list_update?\n" unless keys %data > 1;

	\%data;

=pod

Record update in the PAUSE mailinglists database:

      userid: [CGIP]
maillistname: [The CGI-Perl Developers mailing list]
     address: [/dev/null@localhost] was []
   subscribe: [Mailing list is temporarily closed]

Data entered by Andreas J. Kˆnig.

=cut

	}


sub module_updated     {
	my( $email ) = @_;

	my $body = $email->body;

	open my $fh, '<:utf8', \$body;
	
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
			
		if( m/Data entered by\s+(.*?)\s+\((\S+?)\)/ ) {
			$data{entered_by}{id} = $2;
			$data{entered_by}{name} = $1;
			}
		}

	warn "Problem with mailing_list_update?\n" unless keys %data > 1;

	\%data;

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

	open my $fh, '<:utf8', \$body;

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

	warn "Problem with mailing_list_update?\n" unless keys %data > 1;
		
	return \%data;
	}


sub module_update {
	my( $email ) = @_;

	my $body = $email->body;

	open my $fh, '<:utf8', \$body;
	
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

	warn "Problem with mailing_list_update?\n" unless keys %data > 1;

	\%data;
	}


sub new_module {
	my( $email ) = @_;

	my %captures = $email->body =~ m/
		list \h+ the \h+ following \h+ module:
		\s*
		\R
		\h+ (modid):       \h+      (.*?) \R
		\h+ (DSLIP?):      \h+      (.*?) \R
		\h+ (description): \h+      (.*?) \R
		\h+ (userid):      \h+      (.*?) \R 
		\h+ (chapterid):   \h+      (.*?) \R 
		\h+ (enteredby):   \h+      (.*?) \R 
		\h+ (enteredon):   \h+      (.*?) \R 
		\s+
		The \h+ resulting \h+ entry \h+ will \h+ be:
		/xsi or do{ warn "Did not match new_module!\n"; return };

	my( $id, $name ) = $captures{userid} =~ m/(\S+) \h+ \( (.*?) \)/;
	delete $captures{userid};
	$captures{userid}{id} = $id;
	$captures{userid}{name} = $name;

	\%captures;

=pod

The next version of the Module List will list the following module:

  modid:       Tk::DateEntry
  DSLIP:       RdpO?
  description: Drop down calendar for selecting dates
  userid:      SREZIC (Slaven Rezic)
  chapterid:    8 (User_Interfaces)
  enteredby:   ANDK (Andreas J. Kˆnig)
  enteredon:   Mon Mar  4 12:13:52 2002 GMT

The resulting entry will be:

=cut

	}


sub pause_id_request {
	my( $email ) = @_;

	my $body = $email->body;
	utf8::upgrade( $body );
	
	my %captures = $email->body =~ m/
		Request \h+ to \h+ register \h+ new \h+ user
		\s*
		\R
		\h* (fullname):   \h+      (.*?) \R
		\h* (userid):     \h+      (.*?) \R
		\h* (mail):       \h+      (.*?) \R
		\h* (homepage):   \h+      (.*?) \R 
		\h* (why):
		\s+ (.*?) \s+
		The \h+ following \h+ links
		/xsi or do{ warn "Did not match pause_id_request!\n"; return };

	\%captures;

=pod

Request to register new user

fullname: Michal Ratajsky
  userid: INCOMING
    mail: CENSORED
homepage: 
     why:

    I'd like to contribute MSN and Yahoo messaging protocol classes.

=cut

	}


sub uri_update         {
	my( $email ) = @_;

	my $body = $email->body;

	open my $fh, '<:utf8', \$body;
	
	my %data;
	my $start = 0;
	while( <$fh> ) {
		if( ! $start && m/\ARecord update in the PAUSE uploads database/ ) { $start = 1 }
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

=pod

Record update in the PAUSE uploads database:

       uriid: [I/IL/ILYAM/Mail-CheckUser-1.13.tar.gz]
         uri: [http://martynov.org/tgz//Mail-CheckUser-1.13.tar.gz] was [http://martynov.org/tgz/Mail-CheckUser-1.13.tar.gz]

Data entered by Ilya Martynov (ILYAM).
Please check if they are correct.

=cut

	}


sub user_update {
	my( $email ) = @_;

	my $body = $email->body;

	open my $fh, '<:utf8', \$body;
	
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
		/xsi or do{ warn "Did not match welcome_new_user!\n"; return };

	\%captures;
	}
