package Pod::OOoWriter;
use strict;

# $Id: OOoWriter.pm,v 1.20 2004/06/09 14:57:48 cbouvi Exp $
#
#  Copyright © 2004 Cédric Bouvier
#
#  This library is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License as published by the Free
#  Software Foundation; either version 2 of the License, or (at your option)
#  any later version.
#
#  This library is distributed in the hope that it will be useful, but WITHOUT
#  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
#  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
#  more details.
#
#  You should have received a copy of the GNU General Public License along with
#  this library; if not, write to the Free Software Foundation, Inc., 59 Temple
#  Place, Suite 330, Boston, MA  02111-1307  USA
#
# $Log: OOoWriter.pm,v $
# Revision 1.20  2004/06/09 14:57:48  cbouvi
# Bugfix with nested unordered lists
#
# Revision 1.19  2004/06/09 13:59:05  cbouvi
# Removes the number of a numbered item only at the beginning (was a bug)
#
# Revision 1.18  2004/06/09 11:40:43  cbouvi
# Double quotes are no-longer escaped (caused problems with interior sequences)
#
# Revision 1.17  2004/06/09 08:36:59  cbouvi
# Removed bullets in from POD input, so that only the next paragraph is a bullet
#
# Revision 1.16  2004/06/08 15:38:41  cbouvi
# Added support for numbered list. Code cleanup
#
# Revision 1.15  2004/06/08 14:04:23  cbouvi
# More generic generation of XML tags (less hard-coded)
#
# Revision 1.14  2004/06/04 15:11:12  cbouvi
# Paragraphs after =item now get the list style, instead of default para
#
# Revision 1.13  2004/06/04 14:34:59  cbouvi
# Better handling of lists. Applies the style at list level as well as item level
#
# Revision 1.12  2004/06/03 14:48:06  cbouvi
# Two typos
#
# Revision 1.11  2004/06/03 13:58:20  cbouvi
# Update POD
#
# Revision 1.10  2004/06/02 16:09:56  cbouvi
# Added comments and POD
#
# Revision 1.9  2004/05/25 14:48:49  cbouvi
# Added comments and POD
# Now supports nested =over
# Performs keyword substitution also in meta.xml (document properties)
#
# Revision 1.8  2004/05/14 11:37:17  cbouvi
# Added #para# marker
#
# Revision 1.7  2004/05/13 13:09:55  cbouvi
# Added basic support for ##keyword## substitution
#
# Revision 1.6  2004/05/12 12:46:18  cbouvi
# Added support for =head[34]
#

use Pod::Parser;
use vars qw/ @ISA $VERSION /;

use Archive::Zip qw/ :ERROR_CODES /;
use Unicode::String qw/ latin1 utf8 /;

$VERSION = 0.2;
@ISA = qw/ Pod::Parser /;

use Pod::OOoWriter::XMLParser;

#
# xml_escape
# Substitutes & < and > with their entities
#
sub xml_escape {

    local $_ = $_[0];
    s/&/&amp;/g;
    s/</&lt;/g;
    s/>/&gt;/g;
    return $_;
}

#
# escape
# Prepare a string for insertion into an XML document
# 
sub escape {

    local $_ = $_[0];

    # Trim leading whitespace
    s/\s+$//;

    # Substitute XML entities
    $_ = xml_escape $_;

    # Replace special {tag:s with real (XML) ones
    s/\{tag:/</g;
    s/tag:\}/>/g;

    # Convert to Unicode
    $_ = latin1($_)->utf8();
    return $_;
}

#
# parse_template
# Parse the input OOo Writer template and retrieves the list of tokens (and
# associated styles), the text that precedes the #head1# token, and the text
# that follows the last sibling of the tag that contained #head1#
#
sub parse_template {

    my $self = shift;

    my $ootemplate = $$self{ootemplate};
    my $zip = $self->{zip} ||= new Archive::Zip;

    die "Cannot open $ootemplate\n" if $zip->read($ootemplate) != AZ_OK;
    my $member = $zip->removeMember('content.xml');
    my $xml = $member->contents();

    my $parser = new Pod::OOoWriter::XMLParser;
    $parser->parse($xml);

    $self->{tokens} = $parser->{ooo_tokens};
    $self->{headers} = $parser->{ooo_headers};
    $self->{footers} = $parser->{ooo_footers};
}

#
# flush
# Actually create the output file's content
#
sub flush {

    my $self = shift;

    my $zip = $self->{zip};

    $zip->addString($self->{contents}, 'content.xml');

    for ( qw/ styles meta / ) {
        my $member = $zip->removeMember("$_.xml");
        (my $xml = $member->contents()) =~ s/##(\w+)##/$self->{keywords}{$1}/eg;
        $zip->addString($xml, "$_.xml");
    }

    $zip->writeToFileNamed($self->{outputfile});
}

#
# initialize
#
sub initialize {

    my $self = shift;

    $self->parse_template();
}

#
# begin_pod
#
# An event handler called at the begin of the POD document. Just copy the
# contents of content.xml up to the #head1# marker. This has been made up by
# the code in Pod::OOoWriter::XMLParser
#
sub begin_pod {

    my $self = shift;

    $self->{contents} .= join '', @{$self->{headers}};
}

#
# end_pod
#
# An event handler called at the end of the POD Document. Append the XML code
# that follows the body of the OOo document, then, perform ##keyword##
# substitution in content.xml
#
sub end_pod {

    my $self = shift;

    $self->{contents} .= join '', @{$self->{footers}};
    $self->{contents} =~ s/##(\w+)##/$self->{keywords}{$1}/eg;
}

sub interpolate {

    my ($self, $paragraph, $line_num) = @_;
    local $_ = $self->SUPER::interpolate($paragraph, $line_num);
    s/\s+$//;
    return $_;
}

# rebuild an opening tag, from its name and a hashref of attributes
sub opening_tag {

    my ($tag, $attr) = @{$_[0]};
    my @attr = map qq|$_="| . xml_escape($attr->{$_}) . '"', keys %$attr;

    return '<' . join(' ', grep $_, $tag, @attr) . '>';
}

sub closing_tag {

    my $tag = $_[0][0];
    return "</$tag>";
}

#
# command
#
# an event handler called when a =command is encountered
#
sub command {

    my ($self, $command, $paragraph, $line_num) = @_;

    # resolve any interior sequence
    my $expansion = $self->interpolate($paragraph, $line_num);
    
    # substitute XML entities, convert to XML/Unicode
    $expansion = escape $expansion;

    for ( $command ) {
        $_ eq 'begin' and do {
            $paragraph =~ s/^\s+|\s+$//g;
            if ( $paragraph eq 'OOoWriter' ) {
                $self->{in_keyword_section} = 1 if $paragraph eq 'OOoWriter';
            }
            else {
                $self->{ignore_section} = 1;
            }
            return;
        };
        $_ eq 'end' and do {
            $self->{in_keyword_section} = 0 if $self->{in_keyword_section};
            $self->{ignore_section} = 0;
            return;
        };

        return if $self->{ignore_section};

        /head\d/ and do {
            # Heading: surround the heading with the appropriate tags.
            my $elem = $self->{tokens}{$_};
            $expansion = opening_tag($elem->[0]) . $expansion . closing_tag($elem->[0]);
            last;
        };
        $_ eq 'over' and do {
            # Push undef onto the style stacks. The real style will only be
            # known when encountering the first item (bullet/numbered/...)
            push @{$self->{current_style}}, undef;
            return;
        };
        $_ eq 'back' and do {
            # Close the last item and the (un)ordered list
            my $elem = pop @{$self->{current_style}};
            $expansion = join '', map closing_tag($_), @$elem[1, 2];
            $self->{ooo_in_item}--;
            last;
        };
        $_ eq 'item' and do {
            # Retrieve the style for the current list
            my $elem = $self->{current_style}[-1];
            if ( !$elem ) {
                # Style still unset: this is the first item. Take a look at it
                # and decide about what kind of list (ordered or unordered).
                my $depth = @{$self->{current_style}};
                $elem = $self->{current_style}[-1] = $expansion =~ /^\d+\.?\s*/
                    ? $self->{tokens}{"ol$depth"}
                    : $self->{tokens}{"ul$depth"};
            }
            
            # Remove bullets or leading numbers.
            $expansion =~ s/^[*o-]+\s*//;
            $expansion =~ s/^\d+\.?\s*//;

            # Create a new item, with the text in a paragraph with the
            # appropriate style. Do not close the item yet, since it may
            # contain the subsequent paragraphs.
            if ( $expansion ) {
                $expansion = opening_tag($elem->[1]) . opening_tag($elem->[0]) . $expansion . closing_tag($elem->[0]);
            }
            else {
                $expansion = opening_tag($elem->[1]);
            }

            # Close the previous item if there was one, otherwise, start the list.
            if ( $self->{ooo_in_item} == @{$self->{current_style}} ) {
                $expansion = closing_tag($elem->[1]) . $expansion;
            }
            else {
                $expansion = opening_tag($elem->[2]) . $expansion;
            }

            $self->{ooo_in_item} = @{$self->{current_style}};
            last;
        };
    }
    $self->{contents} .= $expansion;
}

#
# verbatim
#
# An event handler called whenever a verbatim (indented) block is encountered.
#
sub verbatim {

    my ($self, $paragraph, $line_num) = @_;

    return if $self->{ignore_section};

    my $expansion = escape $paragraph;
    for ( $expansion ) {
        s/^\s+// or last;
        my $init_whitespace = $&;# capture the leading white space on 1st line
        s/^$init_whitespace//mg; # and remove the same amount from all others
        s/ /&#xA0;/g;            # turn spaces into non-breaking spaces
        s,\r?\n,<text:line-break/>,g; # XMLize line-breaks
    }

    my $elem = $self->{tokens}{verbatim}[0];
    $expansion = opening_tag($elem) . $expansion . closing_tag($elem);

    $self->{contents} .= $expansion;
}

#
# textblock
#
# An event handler called whenever a normal paragraph is encountered. When
# within a "=begin OOoWriter" section, the paragraph is a keyword declaration
#
sub textblock {

    my ($self, $paragraph, $line_num) = @_;
    return if $self->{ignore_section};

    my $expansion = $self->interpolate($paragraph, $line_num);
    $expansion = escape $expansion;

    if ( $self->{in_keyword_section} ) {
        my ($keyword, $value) = split /\s*:\s*/, $expansion, 2;
        $value =~ s/\s+$//;
        $self->{keywords}{$keyword} = $value;
    }
    else {
        # Paragraphs within lists take a different style
        my $elem = $self->{ooo_in_item}
        ? $self->{current_style}[-1]
        : $self->{tokens}{para};

        $expansion = opening_tag($elem->[0]) . $expansion . closing_tag($elem->[0]);
        $self->{contents} .= $expansion;
    }
}

#
# interior_sequence
#
# This routine gets called by interpolate() to interpolate the interior
# sequences such as B<>, C<>... These will of course be rendered as XML tags,
# but we cannot use < and > as marker right here, since the result string will
# undergo XML escaping later on in the process. Hence the \{tag: and tag:\}
# patterns that we use instead of < and > resp.
#
sub interior_sequence {

    my ($self, $seq_command, $seq_argument) = @_;

    for ( $seq_command ) {
        /^[BCFI]$/ and do {
            my $elem = $self->{tokens}{$seq_command}[0];
            my $open = opening_tag($elem);
            my $close = closing_tag($elem);
            for ( $open, $close ) {
                $_ = "\{tag:" . substr($_, 1, -1) . "tag:\}";
            }
            return $open . $seq_argument . $close;
        };
    }
}

1;

=head1 NAME

Pod::OOoWriter - converts a POD file to an OpenOffice.org Writer document.

=head1 SYNOPSIS

    use Pod::OOoWriter;

    my $p = new Pod::OOoWriter outputfile => 'out.sxw', ootemplate => 'tmpl.sxw';
    $p->parse_from_file('in.pod');
    $p->flush();

=head1 DESCRIPTION

This class generates an OpenOffice.org Writer document by merging a text in POD
format into an existing OOo document that acts as a template. It derives from
Pod::Parser and therefore inherits all its methods.

=head2 Constructor

=over 4

=item B<new> ootemplate => I<TMPL>, outputfile => I<OUT>

Creates and returns an instance of Pod::OOoWriter. I<TMPL> and I<OUT> are
mandatory arguments and are the paths to the OOo template and the output file,
respectively.

=back

=head2 Methods

Pod::OOoWriter inherits all the methods from its ancestor. See L<Pod::Parser>
for details, but parse_from_file() and parse_from_filehandle() are available
for parsing the POD text.

=over 4

=item B<flush>

This methods actually does the job of generating the output file (given to the
constructor as C<outputfile>), based on the template (C<ootemplate>) and the
POD text, parsed by parse_from_file() or parse_from_filehandle().

=back

=head2 Template Format

The template should contain markup that tells Pod::OOoWriter what formatting to
apply when it encounters a given POD directive.

The template must thus contain sample paragraphs in heading style, level 1 to
4. These paragraphs must contain the tokens C<#head1#> to C<#head4#>
respectively. This way, when Pod::OOoWriter encounters a C<=head2> directive,
it will apply the same style than that of the paragraph that contained the
token C<#head2#>.

Similarly, sample paragraphs must be provided for normal text, including the
token C<#para#>, and for verbatim text, including the token C<#verbatim#>. The
sample normal paragraph should also contain tokens C<#bold#>, C<#italic#>,
C<#file#> and C<#code#>, in character styles that denote, respectively, bold,
italic, file names or paths, and code snippets or identifiers.

Samples should also be provided for bulleted, unordered lists, in levels 1 to
3, containing the tokens C<#over4#> to C<#over6#>. 4 is the default indentation
level for the C<=over> directive, hence the seemingly weird choice of tokens.
Alternatively, C<#ul1#> to C<#ul3> can be used instead.

For numbered lists, use tokens C<#ol1#> to C<#ol2#>.

A basic template example is included in directory F<eg/> of the source
distribution.

=head2 Keyword substitution

Keywords surrounded by double hashes (e.g. C<##KEYWORD##>) can be included
anywhere in the OOo template: in the text, in the page headers and footers or
in the document's properties. This allows for defining the document's title, or
the author, or the address of the company producing it, etc.

Values for the keywords must be defined in the POD itself, in a C<=begin
OOoWriter> section. Each paragraph with such a section will be parsed as a
key/value pair, separated by a colon (whitespace on either side of the colon is
allowed and optionnal).

    =begin OOoWriter

    TITLE : Testing Pod::OOoWriter

    AUTHOR: Cédric Bouvier

    =end

Keywords are case-sensitive, and should match C</^\w+$/> (i.e., only letters,
digits and underscores).

=head2 The Parsing

Pod::OOoWriter starts by parsing the template in search for the C<#head1#>
token. Anything before that is copied verbatim to the output. This means that
the template can contain a front page, or a table of contents, as long as they
appear B<before> the token C<#head1#>.

Once C<#head1#> is found, the rest of the template is still parsed in search
for the other tokens, but it is no longer copied to the output. Instead, the
output consists of the POD document, with styles applied according to the
tokens found in the template.

Once the template has been parsed and the POD text merged within, the keyword
substitution occurs.

=head1 BUGS AND LIMITATIONS

The numbered list support is still somewhat buggy. For instance, a numbered
list nested within another would not start with 1, but with the number that
follows the latest item in its parent list, e.g.:

    1.
    2.
        3.
        4.
    3.
    4.

Probably many, many more, and then some.

=back

=head1 SEE ALSO

L<perlpod>, L<Pod::Parser>

=head1 AUTHOR

Copyright © 2004 Cédric Bouvier <cbouvi@cpan.org>

This module is free software. You can redistribute and/or modify it under the
terms of the GNU General Public License.

=cut
