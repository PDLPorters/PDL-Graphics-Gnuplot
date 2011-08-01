use 5.008;
use strict;
use warnings;
use ExtUtils::MakeMaker;

# make sure we can run gnuplot before continuing
{
  unless( open( my $pipe, '|-', 'gnuplot' ))
  {
    print STDERR <<EOM;

Error: "$!"

I tried to execute 'gnuplot' and it didn't work. Since this module is an is an
interface to Gnuplot, it must be installed for the module to be useful. Install
Gnuplot to continue. Use your package manager, or download the source from
http://www.gnuplot.info
EOM

    exit 1;
  }
}


sub MY::libscan
{
    package MY;

    my ($self, $file) = @_;

    # Don't install the README.pod or any .pl file
    return undef if $file =~ /\.pl$|^README.pod/;

    return $self->SUPER::libscan ($file);
}

WriteMakefile(
    NAME                => 'PDL::Graphics::Gnuplot',
    AUTHOR              => q{Dima Kogan <dima@secretsauce.net>},
    VERSION_FROM        => 'lib/PDL/Graphics/Gnuplot.pm',
    ABSTRACT_FROM       => 'lib/PDL/Graphics/Gnuplot.pm',
    ($ExtUtils::MakeMaker::VERSION >= 6.3002
      ? ('LICENSE'=> 'perl')
      : ()),
    PREREQ_PM => { 'Test::More' => 0,
                   'PDL'        => 0,
                   'IPC::Run'   => 0
                 },
    dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean               => { FILES => 'PDL-Graphics-Gnuplot-*' },
);


# reroute the main POD into a separate README.pod if requested. This is here
# purely to generate a README.pod for the github front page
my $POD_header = <<EOF;
=head1 OVERVIEW

This is a Gnuplot-based plotter for PDL. This repository stores the history for
the PDL::Graphics::Gnuplot module on CPAN. Install the module via CPAN. CPAN
page at L<http://search.cpan.org/~dkogan/PDL-Graphics-Gnuplot/lib/PDL/Graphics/Gnuplot.pm>

=cut

EOF

if(exists $ARGV[0] && $ARGV[0] eq 'README.pod')
{
  open MOD, 'lib/PDL/Graphics/Gnuplot.pm' or die "Couldn't open main module";
  open README, '>README.pod'              or die "Couldn't open README.pod";

  print README $POD_header;

  while (<MOD>)
  {
    if (/^=/../^=cut/)
    { print README; }
  }
}
