#!/usr/bin/perl
use strict;
use File::Basename;
use File::Path;
use Getopt::Long;
use HTML::Template;
use Pod::Usage;
use Storable qw(dclone);
use Time::Seconds;

use lib dirname(__FILE__);
use prettyPrintDirView;

my $cregitVersion = "2.0-RC1";
my $filter = "";
my $findRegex = "";
my $filter_lang = 0;
my $help = 0;
my $man = 0;
my $outputFile = undef;
my $overwrite = 0;
my $templateFile = undef;
my $verbose = 0;
my $webRoot = "";
my $webRootRelative = 0;
my $printSingle = 0;
my $printRecursive = 0;
my $dbUpdate = 0;
my $index = 0;

my $printDirPath;
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

sub pre_setup {
    $printDirPath = shift @ARGV; # root/SUBDIR1/SUBDIR2
    $repoDir = shift @ARGV; # original repository
    $sourceDB = shift @ARGV; # token.db
    $authorsDB  = shift @ARGV; # persons.db
    $blametokensDB = shift @ARGV; # blame-token.db
    $outputDir = shift @ARGV; # output directory /home/(users)/public_html

    Usage("Database of tokenized repository does not exist [$sourceDB]", 0) unless -f $sourceDB;
    Usage("Database of authors does not exist [$authorsDB]", 0) unless -f $authorsDB;
    Usage("Database of authors does not exist [$blametokensDB]", 0) unless -f $blametokensDB;
    Usage("Output Directory not found [$outputDir], maybe try to run file view first\n", 0) unless -e $outputDir;

    PrettyPrintDirView::setup_dbi($sourceDB, $authorsDB, $blametokensDB, "");
    print "Updating per file activity table and date group table.." if $dbUpdate;
    PrettyPrintDirView::per_file_activity_dbi() if $dbUpdate; # update per file activity table
    print ".Done!\n" if $dbUpdate;

    # filter for c and c++ programming language
    if ($filter_lang eq "c") {
        $filter = "\\.(h|c).html\$";
        $findRegex = "^.*\\.\\(h\\|c\\)\$";
    } elsif ($filter_lang eq "cpp") {
        $filter = "\\.(h(pp)?|cpp).html\$";
        $findRegex = "^.*\\.\\(h\\(pp\\)\\?\\|cpp\\)\$";
    }

    return 0;
}

sub print_single_dir {
    $printDirPath = substr($printDirPath, 4) if $printDirPath =~ /root/;
    my $directoryPath = File::Spec->catdir($outputDir, $printDirPath);
    my $dirName = ($directoryPath eq $outputDir) ? "root" : basename($directoryPath);

    my $directoryData = content_object($dirName);
    my $breadcrumbsPath = File::Spec->catdir("root/", substr($directoryPath, length $outputDir));
    my $breadcrumbs = PrettyPrintDirView::get_breadcrumbs($breadcrumbsPath);

    $directoryData->{breadcrumbs} = $breadcrumbs;
    $directoryData->{path} = $directoryPath;

    print ++$index." : $breadcrumbsPath..";
    my ($authors, $stats) = PrettyPrintDirView::get_directory_stats($breadcrumbsPath);
    my ($minTime, $maxTime) = PrettyPrintDirView::get_minmax_time($breadcrumbsPath);

    $directoryData->{authors} = dclone $authors;
    $directoryData->{tokens} = $stats->{tokens};
    $directoryData->{author_counts} = $stats->{author_counts};
    $directoryData->{commit_counts} = $stats->{commit_counts};
    $directoryData->{mintime} = $minTime;
    $directoryData->{maxtime} = $maxTime;

    my @dirList = ();
    my @fileList = ();
    my $tokenLen = 0;
    my $fileTokenLen = 0;

    opendir(my $dh, $directoryPath);
    my @contentList = grep {$_ ne '.' and $_ ne '..'} readdir $dh;

    foreach (@contentList) {
        my $currContent = $_;
        # skip hidden file or folder
        next if substr($currContent, 0, 1) eq ".";

        my $content;
        my $contentPath = File::Spec->catfile($directoryPath, $currContent);

        if (-d $contentPath) {
            my $dirSourcePath = substr ($contentPath, (length $outputDir)+1);
            $dirSourcePath = File::Spec->catfile($repoDir, $dirSourcePath);
            next if ! -e $dirSourcePath; # skip irrelevant folder(s)

            my $contentRelativePath = File::Spec->catdir("root/", substr($contentPath, length $outputDir));

            # print "Subdir : [$contentRelativePath]\n";

            my ($contentAuthors, $contentStats) = PrettyPrintDirView::get_content_stats($contentRelativePath, 'd');
            my $dateGroups = PrettyPrintDirView::get_content_dategroup($contentRelativePath, 'd');
            my ($fileCount, $lineCount) = get_file_and_line_counts($dirSourcePath);

            $content = content_object($currContent);
            $content->{tokens} = $contentStats->{tokens};
            $content->{author_counts} = $contentStats->{author_counts};
            $content->{url} = "./".$currContent;
            $content->{authors} = dclone $contentAuthors;
            $content->{dateGroups} = dclone $dateGroups;
            $content->{line_counts} = $lineCount;
            $content->{file_counts} = $fileCount;

            push(@dirList, dclone $content);
        } elsif (-f $contentPath and $contentPath =~ /$filter/) {
            my $fileName = substr ($contentPath, (length $outputDir)+1, (length $contentPath)-(length $outputDir)-6);
            my $sourceFile = File::Spec->catfile($repoDir, $fileName);

            if (! -f $sourceFile) {
                PrettyPrintDirView::Warning("Missing source file $sourceFile ... skipping");
                next;
            }

            # print "File : [$fileName]\n";

            my ($contentAuthors, $contentStats) = PrettyPrintDirView::get_content_stats($fileName, 'f');
            my $dateGroups = PrettyPrintDirView::get_content_dategroup($fileName, 'f');

            $content = content_object(basename($fileName));
            my $fileLines = `wc -l < $sourceFile;`+0;
            $content->{tokens} = $contentStats->{tokens};
            $content->{author_counts} = $contentStats->{author_counts};
            $content->{line_counts} = $fileLines;
            $content->{file_counts} = '-';
            $content->{url} = "./".basename($contentPath);
            $content->{authors} = dclone $contentAuthors;
            $content->{dateGroups} = dclone $dateGroups;

            push(@fileList, dclone $content);
            $fileTokenLen = ($content->{tokens} > $fileTokenLen) ? $content->{tokens} : $fileTokenLen;
        }

        $tokenLen = ($content->{tokens} > $tokenLen) ? $content->{tokens} : $tokenLen;
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
    print ".Done\n";

    closedir($dh);
    return 0;
}

sub print_recursive_dirs {
    $printDirPath = substr($printDirPath, 4) if $printDirPath =~ /root/;
    my $directoryPath = File::Spec->catdir($outputDir, $printDirPath);

    opendir(my $dh, $directoryPath);
    my @contentList = grep {$_ ne '.' and $_ ne '..'} readdir $dh;

    print_single_dir();

    foreach (@contentList) {
        my $currContent = $_;
        # skip hidden file or folder
        next if substr($currContent, 0, 1) eq ".";

        my $contentPath = File::Spec->catfile($directoryPath, $currContent);
        my $contentSourcePath = File::Spec->catdir($repoDir, substr($contentPath, length $outputDir));

        $printDirPath = File::Spec->catdir("root/", substr($contentPath, length $outputDir));

        if (-d $contentPath) {
            if (! -e $contentSourcePath) {
                PrettyPrintDirView::Warning("$contentSourcePath does not exist in repository ... skipping");
                next;
            }
            print_recursive_dirs();
        }
    }

    closedir($dh);
    return 0;
}

# executing linux find command to get file and lin count
sub get_file_and_line_counts {
    my $dirSourcePath = shift @_;
    my $fileCount = `find $dirSourcePath -regex \"$findRegex\" | wc -l `+0;
    my $lineCount = `find $dirSourcePath -regex \"$findRegex\" -exec cat {} + | wc -l`+0;

    return ($fileCount, $lineCount);
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
    $template->param(time_min => $directory->{mintime});
    $template->param(time_max => $directory->{maxtime});
    $template->param(cregit_version => $cregitVersion);
    $template->param(web_root => $webRoot);

    my $file = undef;

    if (-f $outputFile and !$overwrite) {
        print("Output file already exists. Skipping.\n") if $verbose;
        return 0;
    }

    if ($outputFile ne "") {
        open($file, ">", $outputFile) or return PrettyPrintDirView::Error("cannot write to [$outputFile]");
    } else {
        $file = *STDOUT;
    }

    print $file $template->output();
    return 0;
}

sub content_object {
    my $name = shift @_;

    my $contentObject = {
        name          => $name,
        tokens        => 0,
        line_counts   => 0,
        file_counts   => 0,
        author_counts => 0,
        authors       => undef
    };

    return $contentObject;
}

sub print_stats {
    print "Processed: [$index] directories\n";
    my $t = Time::Seconds->new(time-$^T);
    print "Process took [".$t->pretty."] to finish.\n";
    return 0;
}

sub Usage {
    my ($message, $verbose) = @_;
    print STDERR $message, "\n";
    pod2usage(-verbose=>$verbose) if $verbose > 0;
    exit(1);
}

GetOptions(
    "help"              => \$help,
    "man"               => \$man,
    "verbose"           => \$verbose,
    "update"            => \$dbUpdate,
    "template=s"        => \$templateFile,
    "output=s"          => \$outputFile,
    "filter=s"          => \$filter,
    "filter-lang=s"     => \$filter_lang,
    "overwrite"         => \$overwrite,
    "webroot=s"         => \$webRoot,
    "webroot-relative"  => \$webRootRelative,
    "print-single"    => \$printSingle,
    "print-recursive" => \$printRecursive
) or die("Error in command line arguments\n");

exit pod2usage(-verbose=>1) if ($help);
exit pod2usage(-verbose=>2) if ($man);
exit pod2usage(-verbose=>1, -exit=>1) if (!defined(@ARGV[1]));
exit pod2usage(-verbose=>1, -exit=>1) if (not -f @ARGV[1] and not -d @ARGV[1]);
pre_setup;
print_recursive_dirs if ($printRecursive);
print_single_dir if (!$printRecursive);
print_stats;


__END__

# pod
=head1 NAME

prettyPrintDirView2.pl: create the "pretty" output of directories in a git repository

=head1 SYNOPSIS

  prettyPrintDirView2.pl [options] [--print-single] <path> <repoDir> <cregitRepoDB> <authorsDB> <blametokensDB> <outputDir>

  prettyPrintDirView2.pl [options] --print-recursive <path> <reepoDir> <cregitRepoDB> <authorsDB> <blametokensDB> <outputDir>

     Options:
        --help             Brief help message
        --man              Full documentation
        --verbose          Enable verbose output
        --update           Update database activity for each file
        --template         The template file used to generate static html pages
                           Defaults to templates/page.tmpl
        --print-single     Create HTML view for single directory, default is single
        --print-recursive  Create HTML views recursively starts from current directory

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