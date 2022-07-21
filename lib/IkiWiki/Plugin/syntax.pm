package IkiWiki::Plugin::syntax;

use warnings;
use strict;
use Carp;

use IkiWiki;
use Text::VimColor;

our $VERSION    =   '0.9';

our $Syntax     =   undef;

# Module implementation here
sub import { #{{{
	hook(type => "checkconfig", id => "syntax", call => \&checkconfig);
	hook(type => "preprocess", id => "syntax", call => \&preprocess);
} # }}}

sub checkconfig () { #{{{
    # create a reusable object        
    $Syntax = Text::VimColor->new();

    if (not $Syntax) {
        debug("could not create Text::VimColor object; syntax disabled");
    }

    return;
} #}}}

sub preprocess (@) { #{{{
    my %params = (
        type            =>  '',
        description     =>  undef,
        text            =>  undef,
        file            =>  undef,
        linenumbers     =>  0,
        formatcomments  =>  0,
        force_subpage   =>  0,
        page            =>  undef,
        destpage        =>  undef,
        @_
    );
    my  $syntax_html    =   undef;
    my  @extra_params   =   ();

    #   checking plugin availability
    if (not $Syntax) {
        return _build_fail_response('plugin disabled');
    }

    #   checking file type parameter
    if ($params{type}) {
        push( @extra_params, filetype => $params{type} );
    }

    #   if defined a external source file ...
    if (defined($params{file})) {
        # get the real path from the file name
        my $realfile = srcfile( $params{file} );

        if (not -r $realfile) {
            return _build_fail_response('could not read file ' .
                $params{file});
        }
        else {
            debug('syntax highlighting for page ' . $params{file} . 
                  ' from file ' . $realfile );
                  
            $syntax_html = $Syntax->syntax_mark_file( $realfile, @extra_params)->html();

            if ($syntax_html) {
                eval {
                    add_depends($params{page}, $params{file});
                };
            }
            else {
                return _build_fail_response('error in Text::VimColor - ',
                    $realfile);
            }                    
        }            
    } 
    elsif (defined($params{text})) {
        my $text = $params{text};
        $syntax_html = $Syntax->syntax_mark_string( $text, @extra_params )->html();
    }        
    else {
        return _build_fail_response('parameter file or text required');
    }        
    
    #   format comments ?
    $syntax_html = _format_comments($syntax_html, $params{formatcomments})
        if $params{formatcomments};

    #   add line numbers ? 
    $syntax_html = _numered_lines($syntax_html, $params{linenumbers})
        if $params{linenumbers};

    #   build a footer link         
    my $footer_desc = eval { _build_description(\%params); };
    return join("\n",   '<div class="syntax">',
                        '<pre>',
                        $syntax_html,
                        '</pre>',
                        $footer_desc,
                        '</div>' );

} # }}}

sub _dumper_extra_params {
    my %params      =   @_;
    my @pares       =   ();

    foreach my $var (keys(%params)) {
        push(@pares, sprintf('%s=%s', $var, $params{$var}));
    }

    return join(',', @pares);
}    

sub _format_comments {
    my  $html           =   shift;
    my  $formatcomments =   shift;
    my  $formatted      =   '';

    # pending of investigate

    return $html || $formatted;
}

sub _numered_lines {
    my  $html       =   shift;
    my  $counter    =   shift;
    my  $numered    =   '';
    
    # if we haven't a first line number set to first        
    $counter = 1 if not $counter  =~ /^\d+/;

    #   Wrap every line with special class
    foreach my $line (_split_text($html)) {
        #   add a line number
        $numered .= sprintf('<span class="synLineNumber">%5u</span> %s%s',
                            $counter++, $line, "\n" );
    }

    return $numered;
}

sub _split_text {
    my  $text   =   shift;

    return split(/\n/, $text);
}

sub _build_description {
    my  $params_ref     =   shift;
    my  $desc   =   $params_ref->{description} || '';

    # only build a url if we have a file parameter 
    if (defined($params_ref->{file})) {
        my $linktext = sprintf('download file "%s"', $desc ||
                                $params_ref->{file});

        # calling to htmllink 
        $desc = htmllink(   $params_ref->{page}, 
                            $params_ref->{page},
                            $params_ref->{file},
                            1,      # don't turn links into inline html pages
                            $params_ref->{force_subpage} || 0,
                            $linktext
                        );
    }                
    return '<span class="synTitle">' . $desc . '</span>';
}

sub _build_fail_response {
    my  $reason     =   shift;
    my  $file       =   shift;

    return sprintf("[[syntax: %s %s]]\n", $reason, $file);
}

1; 

__END__

=head1 NAME

IkiWiki::Plugin::syntax - Add syntax highlighting to ikiwiki

=head1 SYNOPSIS

In any source page include the following:

    This is the code 

    [[syntax type=perl text="""
    #!/usr/bin/perl
    
    print "Hello, world\n";
    """]]

    and this is my bash profile:

    [[syntax type=bash file="/home/victor/.bash_profile" 
        description="My profile" ]]
  
=head1 DESCRIPTION

This is a simple plugin for IkiWiki, that add support for syntax highlighting
through Vim and his perl interfaz, the cpan module Text::VimColor.

The module register a preprocessor directive named B<syntax>.

=head2 Parameters

The syntax directive has the following parameters:

=over

=item type (optional)

File type for select the syntax vim definition

=item description (optional)

Text description for the html link 

=item text

Source text for syntax highlighting. Mandatory if not exists the file
parameter

=item file

Ikiwiki page name as source text for syntax highlighting. The final html
includes a link to it for direct download.

=item linenumbers

Enable the line numbers in the final html.

=item force_subpage

Parameter for inline funcion to the source page

=back

=head1 CONFIGURATION AND ENVIRONMENT

The module need a vim program installed and functional.

IkiWiki::Plugin::syntax requires no configuration files or environment variables.

=head1 DEPENDENCIES

=over 

=item Text::VimColor 

=item vim

=back

=head1 BUGS AND LIMITATIONS

=over 

=item Break the markdown indented chain. It can't be used between paraggraphs
of one list item. Use it after the item text.

=back

Please report any bugs or feature requests to the author.

=head1 AUTHOR

"Víctor Moral"  C<< victor@taquiones.net >>

=head1 LICENCE AND COPYRIGHT

Copyright (c) 2006, "Víctor Moral".

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License along
with this program; if not, write to the Free Software Foundation, Inc.,
51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.



