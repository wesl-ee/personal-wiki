#!/usr/bin/perl
# Emit Open Graph / Twitter card metadata from rendered page content:
# first paragraph -> description, first image -> card image.
package IkiWiki::Plugin::ogcard;

use warnings;
use strict;
use IkiWiki 3.00;

sub import {
	hook(type => "getsetup", id => "ogcard", call => \&getsetup);
	hook(type => "pagetemplate", id => "ogcard", call => \&pagetemplate);
}

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => 1,
		},
}

# strip tags -> collapse whitespace -> trim
sub textify ($) {
	my $html = shift;
	$html =~ s/<[^>]*>//g;
	$html =~ s/\s+/ /g;
	$html =~ s/^\s+|\s+$//g;
	return $html;
}

sub htmlattr ($) {
	my $s = shift;
	$s =~ s/&/&amp;/g;
	$s =~ s/"/&quot;/g;
	$s =~ s/</&lt;/g;
	$s =~ s/>/&gt;/g;
	return $s;
}

sub pagetemplate (@) {
	my %params = @_;
	my $page = $params{page};
	my $template = $params{template};

	# absolute url to this page
	my $pageurl = urlto($page, undef, 1);

	# content is set on the template before pagetemplate hooks run
	return unless $template->query(name => "content");
	my $content = $template->param("content");
	return unless defined $content && length $content;

	# first paragraph -> description
	my $desc;
	if ($content =~ m{<p\b[^>]*>(.*?)</p>}is) {
		my $text = textify($1);
		if (length $text) {
			$text = substr($text, 0, 297) . "..." if length($text) > 300;
			$desc = $text;
		}
	}

	# first image -> og:image (absolutized against the page url)
	my $img;
	if ($content =~ m{<img\b[^>]*\bsrc\s*=\s*["']([^"']+)["']}is) {
		my $src = $1;
		$src =~ s/&amp;/&/g;
		eval q{use URI};
		if (! $@) {
			$img = URI->new_abs($src, URI->new($pageurl))->as_string;
		}
		else {
			$img = $src;
		}
	}

	my $title = $template->param("title");
	$title = $page unless defined $title && length $title;

	my @og;
	push @og, qq{<meta property="og:type" content="article" />};
	push @og, qq{<meta property="og:title" content="}.htmlattr($title).qq{" />};
	push @og, qq{<meta property="og:site_name" content="}.htmlattr($config{wikiname}).qq{" />};
	push @og, qq{<meta property="og:url" content="}.htmlattr($pageurl).qq{" />};
	if (defined $desc) {
		push @og, qq{<meta property="og:description" content="}.htmlattr($desc).qq{" />};
		push @og, qq{<meta name="description" content="}.htmlattr($desc).qq{" />};
		push @og, qq{<meta name="twitter:description" content="}.htmlattr($desc).qq{" />};
	}
	if (defined $img) {
		push @og, qq{<meta property="og:image" content="}.htmlattr($img).qq{" />};
		push @og, qq{<meta name="twitter:card" content="summary_large_image" />};
		push @og, qq{<meta name="twitter:image" content="}.htmlattr($img).qq{" />};
	}
	else {
		push @og, qq{<meta name="twitter:card" content="summary" />};
	}
	push @og, qq{<meta name="twitter:title" content="}.htmlattr($title).qq{" />};

	if ($template->query(name => "ogcard")) {
		$template->param(ogcard => join("\n", @og));
	}
}

1;
