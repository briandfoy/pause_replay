#!/Users/brian/bin/perls/perl5.14.2
use v5.10;
use utf8;
use strict;
use warnings;

use IO::Interactive qw(interactive);
use File::Spec::Functions;
use Net::NNTP;

select( interactive() );

my $group = 'perl.modules';

my $nntp = Net::NNTP->new('nntp.perl.org');
my( $count, $first, $last ) = $nntp->group( $group );
say "$count, $first, $last";

my $dir = $group;
mkdir $dir, 0755 unless -d $dir;

foreach my $i ( reverse $first .. $last ) {
	last if $i < 53_000;
	my $file = catfile( $dir, "$i.txt" );
	next if -s $file;
	open my $fh, '>', $file;
	my $article = $nntp->article( $i, $fh );
	close $fh;
	printf "%s: %d bytes\n", $file, -s $file;
	sleep 1;
	}

$nntp->quit;

if( $ENV{PERL_PAUSE_COMMIT} ) {
	system "git add perl.modules 2>&1";
	system "git commit -a -m 'Added the latest PAUSE posts' 2>&1";
	system "git push 2>&1";
	}

=head1 NAME

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 AVAILABILITY

=head1 AUTHOR

brian d foy C<< <brian.d.foy@gmail.com> >>

=head1 COPYRIGHT

Copyright 2012-2017, brian d foy C<< <brian.d.foy@gmail.com> >>

=cut
