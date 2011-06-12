use 5.006;
use strict;
use warnings;
use ExtUtils::MakeMaker;


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
    PREREQ_PM => {
        'Test::More' => 0,
    },
    dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean               => { FILES => 'PDL-Graphics-Gnuplot-*' },
);


# reroute the main POD into a separate README.pod if requested. This is here
# purely to generate a README.pod for the github front page

if(exists $ARGV[0] && $ARGV[0] eq 'README.pod')
{
  open MOD, 'lib/PDL/Graphics/Gnuplot.pm' or die "Couldn't open main module";
  open README, '>README.pod'              or die "Couldn't open README.pod";

  while (<MOD>)
  {
    if (/^=/../^=cut/)
    { print README; }
  }
}
