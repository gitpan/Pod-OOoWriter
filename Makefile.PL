use ExtUtils::MakeMaker;
WriteMakefile(
    NAME          => 'Pod::OOoWriter',
    VERSION_FROM  => 'lib/Pod/OOoWriter.pm',
    PREREQ_PM     => { 
        'Archive::Zip'    => 0,
        'Pod::Parser'     => 0,
        'Unicode::String' => 0,
        'XML::Parser'     => 0,
    },
    EXE_FILES     => [ 'bin/pod2ooo' ],
    ABSTRACT_FROM => 'lib/Pod/OOoWriter.pm',
    AUTHOR        => 'Cédric Bouvier <cbouvi@cpan.org>',
);
