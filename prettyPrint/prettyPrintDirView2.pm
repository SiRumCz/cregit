package PrettyPrintDirView2;
use strict;
use Date::Parse;
use Date::Format;
use DBI;
use File::Basename;
use File::Path;

my $dbh;
my $fileAuthorsSth;
my $fileCommitsSth;
my $dirAuthorsSth;
my $dirCommitsSth;

my $perFileActivityDB = "activity.db";
my $perFileActivityTable = "perfileactivity";

# get breadcrumbs for HTML view
sub get_breadcrumbs {
    my $dirPath = shift @_;

    my @breadcrumbs = ();
    my @dirs = File::Spec->splitdir($dirPath);

    my $pos = scalar(@dirs)-1;
    for (my $i=0; $i<$pos; $i++) {
        my $name = @dirs[$i];
        my $path = "../" x ($pos-$i);

        push (@breadcrumbs, {name => $name, path => $path});
    }

    return \@breadcrumbs;
}

sub get_file_stats {
    my $filename = shift @_;
    my $dirAuthorsCached = shift @_;

    my @authors = ();
    my @commits = ();
    my $fileStats;
    my $tokenCounts = 0;
    my $result;

    # fetch authors
    $result = $fileAuthorsSth->execute($filename, $filename, $filename);
    my $authorsMeta = $fileAuthorsSth->fetchall_arrayref;

    if (! defined $result) {
        Warning("Unable to retrieve authors for [$filename]");
        goto FETCHCOMMITS;
    }

    my $authorOthers = {
        id                => 60,
        color_id          => "Black",
        name              => "Others",
        tokens            => 0,
        token_proportion  => 0.0,
        commits           => 0,
        commit_proportion => 0.0
    };
    foreach(@{$authorsMeta}) {
        my @currAuthor = @{$_};
        @currAuthor = ("","Unknown", 0, 0.0, 0, 0.0) unless (scalar @currAuthor == 6);

        my $currAuthor = {
            name              => @currAuthor[1],
            tokens            => @currAuthor[2],
            token_proportion  => @currAuthor[3],
            commits           => @currAuthor[4],
            commit_proportion => @currAuthor[5],
        };

        if (defined $dirAuthorsCached->{@currAuthor[0]}) {
            # in rank 60, inherits id and color code
            $currAuthor->{id} = $dirAuthorsCached->{@currAuthor[0]}->{id};
            $currAuthor->{color_id} = $dirAuthorsCached->{@currAuthor[0]}->{color_id};
            $currAuthor->{token_percent} = sprintf("%.2f\%", 100.0*$currAuthor->{token_proportion});
            $currAuthor->{commit_percent} = sprintf("%.2f\%", 100.0*$currAuthor->{commit_proportion});

            push (@authors, $currAuthor);
        } else {
            $authorOthers->{tokens} += $currAuthor->{tokens};
            $authorOthers->{token_proportion} += $currAuthor->{token_proportion};
            $authorOthers->{commits} += $currAuthor->{commits};
            $authorOthers->{commit_proportion} += $currAuthor->{commit_proportion};
        }

        $tokenCounts += @currAuthor[2];
    }

    if ($authorOthers->{commits} != 0) {
        $authorOthers->{token_percent} = sprintf("%.2f\%", 100.0*$authorOthers->{token_proportion});
        $authorOthers->{commit_percent} = sprintf("%.2f\%", 100.0*$authorOthers->{commit_proportion});
        push (@authors, $authorOthers);
    }

    FETCHCOMMITS:
    # fetch commits
    $result = $fileCommitsSth->execute($filename);
    my $commitsMeta = $fileCommitsSth->fetchall_arrayref;

    if (! defined $result) {
        Warning("Unable to retrieve commits for [$filename]");
        goto GETFILESTATS;
    }

    foreach (@{$commitsMeta}) {
        my @currCommit = @{$_};
        @currCommit = ("","Unknown", "") unless (scalar @currCommit == 3);

        my $authorName = (! defined $dirAuthorsCached->{@currCommit[1]}) ? "Others" : @currCommit[2];

        push (@commits, {
            cid    => @currCommit[0],
            author => $authorName,
            epoch  => str2time(@currCommit[2])
        });
    }

    GETFILESTATS:
    # get file stats : token counts, author counts, commit counts
    $fileStats->{tokens} = $tokenCounts;
    $fileStats->{author_counts} = scalar @{$authorsMeta};
    $fileStats->{commit_counts} = scalar @{$commitsMeta};

    return ([@authors], [@commits], $fileStats);
}

sub get_directory_stats {
    my $dirPath = shift @_;

    my $bindingVar = ($dirPath eq "root") ? "%" : substr($dirPath, 5)."/%";
    my @authors = ();
    my @commits = ();
    my $fileStats;
    my $tokenCounts = 0;
    my $result;

    my $dirAuthorsCached;

    # fetch authors
    $result = $dirAuthorsSth->execute($bindingVar, $bindingVar, $bindingVar);
    my $authorsMeta = $dirAuthorsSth->fetchall_arrayref;

    if (! defined $result) {
        Warning("Unable to retrieve authors for [$dirPath]");
        goto FETCHCOMMITS; # skip authors
    }

    my $index = 0;
    my $indexLimit = 60; # only keep data for top 60 authors
    my $authorOthers = {
        id                => 60,
        color_id          => "Black",
        name              => "Others",
        tokens            => 0,
        token_proportion  => 0.0,
        commits           => 0,
        commit_proportion => 0.0
    };
    foreach(@{$authorsMeta}) {
        my @currAuthor = @{$_};
        @currAuthor = ("","Unknown", 0, 0.0, 0, 0.0) unless (scalar @currAuthor == 6);
        my $currAuthor = {
            id                => $index,
            color_id          => $index,
            name              => @currAuthor[1],
            tokens            => @currAuthor[2],
            token_proportion  => @currAuthor[3],
            token_percent     => sprintf("%.2f\%", 100.0*@currAuthor[3]),
            commits           => @currAuthor[4],
            commit_proportion => @currAuthor[5],
            commit_percent    => sprintf("%.2f\%", 100.0*@currAuthor[5])
        };

        if ($index < $indexLimit) {
            push (@authors, $currAuthor);

            # cache data
            $dirAuthorsCached->{@currAuthor[0]} = $currAuthor;
        } else {
            $authorOthers->{tokens} += $currAuthor->{tokens};
            $authorOthers->{token_proportion} += $currAuthor->{token_proportion};
            $authorOthers->{commits} += $currAuthor->{commits};
            $authorOthers->{commit_proportion} += $currAuthor->{commit_proportion};
        }

        $tokenCounts += $currAuthor->{tokens};
        $index++;
    }

    if ($index > 60) {
        $authorOthers->{token_percent} = sprintf("%.2f\%", 100.0*$authorOthers->{token_proportion});
        $authorOthers->{commit_percent} = sprintf("%.2f\%", 100.0*$authorOthers->{commit_proportion});
        push (@authors, $authorOthers);
    }

    FETCHCOMMITS:
    $result = $dirCommitsSth->execute($bindingVar);
    my $commitsMeta = $dirCommitsSth->fetchall_arrayref;

    if (! defined $result) {
        Warning("Unable to retrieve commits for [$dirPath]");
        goto GETFILESTATS; # skip commits
    }

    foreach (@{$commitsMeta}) {
        my @currCommit = @{$_};
        @currCommit = ("","Unknown", "Unknown", "") unless (scalar @currCommit == 4);

        my $authorName = (! defined $dirAuthorsCached->{@currCommit[1]}) ? "Others" : @currCommit[2];

        my $currCommit = {
            cid    => @currCommit[0],
            author => $authorName,
            epoch  => str2time(@currCommit[3])
        };

        push (@commits, $currCommit);
    }

    GETFILESTATS:
    # get file stats : token counts, author counts, commit counts
    $fileStats->{tokens} = $tokenCounts;
    $fileStats->{author_counts} = scalar @{$authorsMeta};
    $fileStats->{commit_counts} = scalar @{$commitsMeta};

    return ([@authors], [@commits], $fileStats, $dirAuthorsCached);
}

sub setup_dbi {
    my ($sourceDB, $authorsDB, $blametokensDB, $queryKey) = @_;

    my ($dbName, $dbDir) = fileparse($sourceDB);
    $perFileActivityDB = File::Spec->catfile($dbDir, $perFileActivityDB);
    my $dsn = "dbi:SQLite:dbname=$perFileActivityDB";
    my $user = "";
    my $password = "";
    my $options = { RaiseError => 1, AutoCommit => 1 };
    $dbh = DBI->connect($dsn, $user, $password, $options) or die $DBI::errstr;
    $dbh->do("attach database '$authorsDB' as authorsdb;");
    $dbh->do("attach database '$sourceDB' as sourcedb;");
    $dbh->do("attach database '$blametokensDB' as blametokensdb;");
}

sub per_file_activity_dbi {
    print "Updating per file activity table ..";
    $dbh->do("DROP TABLE IF EXISTS $perFileActivityTable;");
    $dbh->do(
        "CREATE TABLE $perFileActivityTable (
        filename text,
        personid text,
        personname text,
        originalcid text,
        tokens int,
        autdate text);"
    );
    $dbh->do(
        "WITH t1 AS (SELECT filename, cid, COUNT(cid) AS tokenspercid FROM blametoken
        GROUP BY filename, cid) INSERT INTO $perFileActivityTable SELECT filename,
        personid, COALESCE(personname, 'Unknown'), originalcid, tokenspercid AS tokens,
        autdate FROM t1 LEFT JOIN commits ON (t1.cid=commits.cid) LEFT JOIN commitmap
        ON (t1.cid=commitmap.cid) LEFT JOIN emails ON (autname=emailname AND autemail
        =emailaddr) LEFT JOIN persons USING (personid) ORDER BY filename, tokens DESC;"
    );
    print ".Done!\n";
}

sub prepare_dbi {
    $fileAuthorsSth = $dbh->prepare(
        "SELECT personid, personname, SUM(tokens) AS tokens, COALESCE(CAST(SUM(tokens) AS float) /
        NULLIF(CAST((SELECT SUM(tokens) FROM $perFileActivityTable WHERE filename=?) AS float)
        , 0), 0) AS token_proportion, COUNT(DISTINCT originalcid) AS commits, COALESCE(
        CAST(COUNT(DISTINCT originalcid) AS float) / NULLIF(CAST((SELECT COUNT(DISTINCT
        originalcid) FROM $perFileActivityTable WHERE filename=?) AS float), 0), 0) AS
        commit_proportion FROM $perFileActivityTable WHERE filename=? GROUP BY personid
        ORDER BY tokens DESC;"
    ); # personid|personname|tokens|token_proportion|commits|commit_proportion
    $fileCommitsSth = $dbh->prepare(
        "SELECT DISTINCT originalcid, personid, personname, autdate FROM $perFileActivityTable
        WHERE filename=?;"
    );

    $dirAuthorsSth = $dbh->prepare(
        "SELECT personid, personname, SUM(tokens) AS tokens, COALESCE(CAST(SUM(tokens) AS float) /
        NULLIF(CAST((SELECT SUM(tokens) FROM $perFileActivityTable WHERE filename LIKE ? ) AS float)
        , 0), 0) AS token_proportion, COUNT(DISTINCT originalcid) AS commits, COALESCE( CAST(COUNT(
        DISTINCT originalcid) AS float) / NULLIF(CAST((SELECT COUNT(DISTINCT originalcid) FROM
        $perFileActivityTable WHERE filename LIKE ?) AS float), 0), 0) AS commit_proportion FROM
        $perFileActivityTable WHERE filename LIKE ? GROUP BY personid ORDER BY tokens DESC;"
    );
    $dirCommitsSth = $dbh->prepare(
        "SELECT DISTINCT originalcid, personid, personname, autdate FROM $perFileActivityTable WHERE
        filename LIKE ?;"
    );
}

sub Error {
    my $message = shift @_;
    print STDERR "Error: ", $message, "\n";
    return 1;
}

sub Warning {
    my $message = shift @_;
    print STDERR "Warning: ", $message, "\n";
    return 1;
}

1;