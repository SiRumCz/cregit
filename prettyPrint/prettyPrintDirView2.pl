#!/usr/bin/perl
use strict;
use File::Basename;
use Getopt::Long;
use HTML::Template;
use Pod::Usage;
use Storable qw(dclone);

use lib dirname(__FILE__);
use prettyPrintDirView2;

my $cregitVersion = "2.0-RC1";
my $filter = "";
my $filter_lang = 0;
my $help = 0;
my $man = 0;
my $outputFile = undef;
my $overwrite = 0;
my $templateFile = undef;
my $verbose = 0;
my $webRoot = "";
my $webRootRelative = 0;
my $dbUpdate = 0;
my $index = 0;
my $warningCount = 0;

my $sourceDB;
my $authorsDB;
my $blametokensDB;
my $repoDir;
my $outputDir;

my $defaultTemplate = dirname(__FILE__) . "/templates/directory.tmpl";
my $templateParams = {
    loop_context_vars => 1,
    die_on_bad_params => 0,
};

sub print_dir_info {
    $repoDir = shift @ARGV; # original repository
    $sourceDB = shift @ARGV; # token.db
    $authorsDB  = shift @ARGV; # persons.db
    $blametokensDB = shift @ARGV; # blame-token.db
    $outputDir = shift @ARGV; # output directory /home/(users)/public_html

    Usage("Database of tokenized repository does not exist [$sourceDB]", 0) unless -f $sourceDB;
    Usage("Database of authors does not exist [$authorsDB]", 0) unless -f $authorsDB;
    Usage("Database of authors does not exist [$blametokensDB]", 0) unless -f $blametokensDB;
    Usage("Output Directory not found [$outputDir], maybe try to run file view first\n", 0) unless -e $outputDir;


    PrettyPrintDirView2::setup_dbi($sourceDB, $authorsDB, $blametokensDB, "");
    PrettyPrintDirView2::per_file_activity_dbi() if $dbUpdate; # update per file activity table
    PrettyPrintDirView2::prepare_dbi();

    # filter for c and c++ programming language
    if ($filter_lang eq "c") {
        $filter = "\\.(h|c).html\$";
    } elsif ($filter_lang eq "cpp") {
        $filter = "\\.(h(pp)?|cpp).html\$";
    }

    my $errorCode = process_directory($outputDir, $outputDir);

    return 0;
}

sub process_directory {
    my $rootPath = shift @_;
    my $dirPath = shift @_;

    my $dirName = basename($dirPath);
    $dirName = ($dirPath eq $rootPath) ? "root" : $dirName;
    my $directoryData = content_object($dirName);
    my $breadcrumbsPath = File::Spec->catdir("root/", substr($dirPath, length $rootPath));
    my $breadcrumbs = PrettyPrintDirView2::get_breadcrumbs($breadcrumbsPath);
    $directoryData->{breadcrumbs} = $breadcrumbs;
    $directoryData->{path} = $dirPath;

    print "Directory: $breadcrumbsPath \nGetting directory stats..";

    # get directory stats : authors, commits, (token counts, author counts, commit counts), cached data
    my ($authors, $commits, $fileStats, $dirAuthorsCached) = PrettyPrintDirView2::get_directory_stats($breadcrumbsPath);
    print ".Done!\n";

    $directoryData->{tokens} = $fileStats->{tokens};
    $directoryData->{authors} = dclone $authors;
    $directoryData->{commits} = dclone $commits;
    $directoryData->{author_counts} = $fileStats->{author_counts};
    $directoryData->{commit_counts} = $fileStats->{commit_counts};

    my @dirList = ();
    my @fileList = ();
    my $tokenLen = 0;
    my $fileTokenLen = 0;

    opendir(my $dh, $dirPath);
    my @contentList = grep {$_ ne '.' and $_ ne '..'} readdir $dh;

    foreach (@contentList) {
        my $currContent = $_;
        # skip hidden file or folder
        next if substr($currContent, 0, 1) eq ".";

        my $content;
        my $contentPath = File::Spec->catfile($dirPath, $currContent);

        if (-d $contentPath) {
            my $dirSourcePath = substr ($contentPath, (length $rootPath)+1);
            $dirSourcePath = File::Spec->catfile($repoDir, $dirSourcePath);
            next if ! -e $dirSourcePath; # skip irrelevant folder(s)

            $content = process_directory($rootPath, $contentPath);

            my $contentDirPath = File::Spec->catdir("root/", substr($contentPath, length $rootPath));
            ($authors, $commits, $fileStats) = PrettyPrintDirView2::get_subdir_stats($contentDirPath, $dirAuthorsCached);

            $content->{tokens} = $fileStats->{tokens};
            $content->{author_counts} = $fileStats->{author_counts};
            $content->{commit_counts} = $fileStats->{commit_counts};
            $content->{url} = "./".basename($contentPath);

            $content->{authors} = dclone $authors;
            $content->{commits} = dclone $commits;

            # my $dateGroups = PrettyPrintDirView2::commits_to_dategroup(\@{$commits}, \@{$authors});
            my $dateGroups = PrettyPrintDirView2::commits_to_dategroup(\@{$commits}, $dirAuthorsCached);
            my @sortedDateGroup = (defined $dateGroups) ? sort { $a->{timestamp} <=> $b->{timestamp} } @{$dateGroups} : ();
            $content->{dateGroups} = [@sortedDateGroup];

            # update largest token
            $tokenLen = ($tokenLen < $content->{tokens}) ? $content->{tokens} : $tokenLen;

            push(@dirList, dclone $content);

        } elsif (-f $contentPath and $contentPath =~ /$filter/) {
            print(++$index . ": $contentPath\n") if $verbose;

            my $fileName = substr ($contentPath, (length $rootPath)+1, (length $contentPath)-(length $rootPath)-6);
            my $sourceFile = File::Spec->catfile($repoDir, $fileName);

            if (! -f $sourceFile) {
                $warningCount += PrettyPrintDirView2::Warning("Missing source file $sourceFile");
                next;
            }
            $content = content_object(basename($fileName));
            ($authors, $commits, $fileStats) = PrettyPrintDirView2::get_file_stats($fileName, $dirAuthorsCached);

            my $fileLines = `wc -l < $sourceFile;`+0;
            $content->{tokens} = $fileStats->{tokens};
            $content->{author_counts} = $fileStats->{author_counts};
            $content->{commit_counts} = $fileStats->{commit_counts};
            $content->{line_counts} = $fileLines;
            $content->{file_counts} = '-';
            $content->{url} = "./".basename($contentPath);

            $content->{authors} = dclone $authors;
            $content->{commits} = dclone $commits;

            # my $dateGroups = PrettyPrintDirView2::commits_to_dategroup(\@{$commits}, \@{$authors});
            my $dateGroups = PrettyPrintDirView2::commits_to_dategroup(\@{$commits}, $dirAuthorsCached);
            my @sortedDateGroup = (defined $dateGroups) ? sort { $a->{timestamp} <=> $b->{timestamp} } @{$dateGroups} : ();
            $content->{dateGroups} = [@sortedDateGroup];

            $tokenLen = ($tokenLen < $content->{tokens}) ? $content->{tokens} : $tokenLen;
            $fileTokenLen = ($fileTokenLen < $content->{tokens}) ? $content->{tokens} : $fileTokenLen;

            push(@fileList, dclone $content);
        }

        # update line counts and file counts
        $directoryData->{line_counts} += $content->{line_counts};
        $directoryData->{file_counts} += ($content->{file_counts} eq '-') ? 1 : $content->{file_counts};
    }

    my $lengthPercentage;
    # update content width
    foreach (@dirList) {
        my $currDir = $_;

        $lengthPercentage = ($tokenLen == 0) ? 0 : 100.0 * $currDir->{tokens} / $tokenLen;
        $currDir->{width} = sprintf("%.2f\%", $lengthPercentage);

        foreach (@{$_->{dateGroups}}) {
            $lengthPercentage = ($currDir->{tokens} == 0) ? 0 : 100.0 * $_->{total_tokens} / $currDir->{tokens};
            $_->{width} = sprintf("%.2f\%", $lengthPercentage);
        }
    }

    foreach (@fileList) {
        my $currFile = $_;

        $lengthPercentage = ($tokenLen == 0) ? 0 : 100.0 * $currFile->{tokens} / $tokenLen;
        $currFile->{width} = sprintf("%.2f\%", $lengthPercentage);
        $lengthPercentage = ($fileTokenLen == 0) ? 0 : 100.0 * $currFile->{tokens} / $fileTokenLen;
        $currFile->{width_in_files} = sprintf("%.2f\%", $lengthPercentage);

        foreach (@{$_->{dateGroups}}) {
            $lengthPercentage = ($currFile->{tokens} == 0) ? 0 : 100.0 * $_->{total_tokens} / $currFile->{tokens};
            $_->{width} = sprintf("%.2f\%", $lengthPercentage);
        }
    }

    # print HTML view
    print_directory($directoryData, \@dirList, \@fileList);

    # return the directory data for parent dir to use
    return $directoryData;
}

sub print_directory {
    my $directory = shift @_;
    my @dirList = @{shift @_};
    my @fileList = @{shift @_};

    my $outputFile = File::Spec->catfile($directory->{path}, "index.html");
    my ($fileName, $fileDir) = fileparse($outputFile);
    my $relativePath = File::Spec->abs2rel($outputDir, $fileDir);
    $webRoot = $relativePath if $webRootRelative;
    $templateFile = $templateFile ? $templateFile : $defaultTemplate;
    my @contributorsByName = sort {$a->{name} cmp $b->{name}} @{$directory->{authors}};
    my @sortedDirList = sort {$a->{name} cmp $b->{name}} @dirList;
    my @sortedFileList = sort {$a->{name} cmp $b->{name}} @fileList;

    my $template = HTML::Template->new(filename => $templateFile, %$templateParams);

    $template->param(directory_name => $directory->{name});
    $template->param(web_root => $webRoot);
    $template->param(breadcrumb_nav => $directory->{breadcrumbs});
    $template->param(contributors_by_name => \@contributorsByName);
    $template->param(contributors_count => $directory->{author_counts});
    $template->param(contributors => $directory->{authors});
    $template->param(total_tokens => $directory->{tokens});
    $template->param(total_commits => $directory->{commit_counts});
    $template->param(has_subdir => scalar @dirList);
    $template->param(has_file => scalar @fileList);
    $template->param(directory_list => \@sortedDirList);
    $template->param(file_list => \@sortedFileList);
    $template->param(cregit_version => $cregitVersion);
    $template->param(has_hidden => (scalar @contributorsByName)>20);
    $template->param(time_min => $directory->{commits}[0]->{epoch});
    $template->param(time_max => $directory->{commits}[(scalar @{$directory->{commits}})-1]->{epoch});

    my $file = undef;

    if (-f $outputFile and !$overwrite) {
        print("Output file already exists. Skipping.\n") if $verbose;
        return 0;
    }

    if ($outputFile ne "") {
        open($file, ">", $outputFile) or return PrettyPrint::Error("cannot write to [$outputFile]");
    } else {
        $file = *STDOUT;
    }

    print "Generating directory view of [$directory->{path}]...";
    print $file $template->output();
    print ".Done! \n";

    return 0;
}

sub content_object {
    my $name = shift @_;

    my $contentObject = {
        name          => $name,
        tokens        => 0,
        commit_counts => 0,
        line_counts   => 0,
        file_counts   => 0,
        author_counts => 0,
        authors       => undef,
        commits       => undef
    };

    return $contentObject;
}

sub Usage {
    my ($message, $verbose) = @_;
    print STDERR $message, "\n";
    pod2usage(-verbose=>$verbose) if $verbose > 0;
    exit(1);
}

GetOptions(
    "help" => \$help,
    "man" => \$man,
    "verbose" => \$verbose,
    "update" => \$dbUpdate,
    "template=s" => \$templateFile,
    "output=s" => \$outputFile,
    "filter=s" => \$filter,
    "filter-lang=s" => \$filter_lang,
    "overwrite" => \$overwrite,
    "webroot=s" => \$webRoot,
    "webroot-relative" => \$webRootRelative,
) or die("Error in command line arguments\n");

exit pod2usage(-verbose=>1) if ($help);
exit pod2usage(-verbose=>2) if ($man);
exit pod2usage(-verbose=>1, -exit=>1) if (!defined(@ARGV[0]));
exit pod2usage(-verbose=>1, -exit=>1) if (not -f @ARGV[0] and not -d @ARGV[0]);
exit print_dir_info;

__END__

# pod
=head1 NAME

  prettyPrintDirView2.pl: create the "pretty" output of directories detailed blame information in a git repository

=head1 SYNOPSIS

  prettyPrintDirView2.pl [options] <sourceFile> <cregitRepoDB> <authorsDB> <blametokensDB> <outputDir>

  prettyPrintDirView2.pl [options] <repoDir> <cregitRepoDB> <authorsDB> <blametokensDB> <outputDir>

     Options:
        --help             Brief help message
        --man              Full documentation
        --verbose          Enable verbose output
        --update           Update database activity for each file
        --template         The template file used to generate static html pages
                           Defaults to templates/page.tmpl


     Options: (single)
        --output           The output file. Defaults to STDOUT.
        --webroot          The web_root template parameter value.
                           Defaults to empty
        --template-var     Defines additional template variables.
                           Usage: --template-var [variable]=[value]

     Options: (multi)
        --overwrite        Overwrite existing files that have previously been generated.
        --webroot          The web_root template parameter value.
                           Defaults to empty
        --webroot-relative Specifies that the value of webroot should
                           be set based on the relative path of the file
                           in relation to the output directory.
        --filter           A regex file filter for processed files.
        --filter-lang      Filters input files by language
                               c      *.c|*.h
                               cpp    *.cpp|*.h|*.hpp

# Pod block end
=cut
