package PrettyPrintDirView;
use strict;

use Date::Parse;
use Date::Format;
use DBI;
use File::Basename;
use File::Path;

# database handle and statement handle
my $dbh;
my $dirAuthorsSth;
my $dirAuthorOthersSth;
my $dirCommitAndTokenCountSth;
my $subDirAuthorsSth;
my $subDirAuthorOthersSth;
my $subDirTokenCountSth;
my $subDirDateGroupSth;
my $fileAuthorsSth;
my $fileAuthorOthersSth;
my $fileTokenCountSth;
my $fileDateGroupSth;
my $minTimeSth;
my $maxTimeSth;

my $perFileActivityDB = "activity.db";
my $perFileActivityTable = "perfileactivity";
my $dategroupTable = "perfiledategroup";
my $directoryTmpTable = "tmp";
my $authorLimit = 60; # max number of authors to keep for each directory

# return authors list and stats (author count, commit count, token count)
sub get_directory_stats {
    my $dirPath = shift @_;

    # create directory stats table
    create_directory_table_dbi($dirPath);

    my @authors = ();
    my $stats;
    my $result;

    # fetch authors
    $result = $dirAuthorsSth->execute();
    my $authorsMeta = $dirAuthorsSth->fetchall_arrayref;

    if (!defined $result) {
        Warning("Unable to retrieve authors for [$dirPath]");
        goto FETCHFILESTATS;
    }

    my $authorCount = $dirAuthorsSth->rows;
    my $index = 0;
    foreach(@{$authorsMeta}) {
        last if ($index == $authorLimit);

        my @currAuthor = @{$_};
        @currAuthor = ($index, $index, "", "Unknown", 0, 0.0, 0, 0.0) unless (scalar @currAuthor == 8);

        my $author = {
            id                => @currAuthor[0],
            color_id          => @currAuthor[1],
            name              => @currAuthor[3],
            tokens            => @currAuthor[4],
            token_proportion  => @currAuthor[5],
            commits           => @currAuthor[6],
            commit_proportion => @currAuthor[7],
            token_percent     => sprintf("%.2f\%", 100.0 * @currAuthor[5]),
            commit_percent    => sprintf("%.2f\%", 100.0 * @currAuthor[7])
        };

        push(@authors, $author);
        $index++;
    }

    if ($authorCount > $authorLimit) {
        $result = $dirAuthorOthersSth->execute();
        my @authorOther = $dirAuthorOthersSth->fetchrow();

        if (!defined($result) or scalar(@authorOther) != 7) {
            Warning("Unable to retrieve author Others for [$dirPath]");
            @authorOther = (60, "Black", "Others", 0, 0.0, 0, 0.0);
        }

        push (@authors, {
            id                => @authorOther[0],
            color_id          => @authorOther[1],
            name              => @authorOther[2],
            tokens            => @authorOther[3],
            token_proportion  => @authorOther[4],
            commits           => @authorOther[5],
            commit_proportion => @authorOther[6],
            token_percent     => sprintf("%.2f\%", 100.0 * @authorOther[4]),
            commit_percent    => sprintf("%.2f\%", 100.0 * @authorOther[6])
        });
    }

    FETCHFILESTATS:
    $result = $dirCommitAndTokenCountSth->execute();
    my @statsMeta = $dirCommitAndTokenCountSth->fetchrow();

    if (! defined $result or scalar(@statsMeta) != 2) {
        Warning("Unable to retrieve stats for [$dirPath]");
        @statsMeta = (0, 0);
    }

    $stats->{commit_counts} = @statsMeta[0];
    $stats->{tokens} = @statsMeta[1];
    $stats->{author_counts} = $authorCount;

    return ([@authors], $stats);
}

sub get_content_stats {
    my $contentPath = shift @_;
    my $type = shift @_;

    my $bindingVar;
    my $result;
    my $authorsMeta;
    my $authorCount;
    if ('f' eq $type) {
        $bindingVar = $contentPath;
        # fetch authors
        $result = $fileAuthorsSth->execute($bindingVar, $bindingVar, $bindingVar);
        $authorsMeta = $fileAuthorsSth->fetchall_arrayref;
        $authorCount = $fileAuthorsSth->rows;
    } elsif ('d' eq $type) {
        $bindingVar = ($contentPath eq "root") ? "%" : substr($contentPath, 5)."/%";
        # fetch authors
        $result = $subDirAuthorsSth->execute($bindingVar, $bindingVar, $bindingVar);
        $authorsMeta = $subDirAuthorsSth->fetchall_arrayref;
        $authorCount = $subDirAuthorsSth->rows;
    }

    my @authors = ();
    my $stats;

    if (!defined $result) {
        Warning("Unable to retrieve authors for [$contentPath]");
        goto FETCHFILESTATS;
    }

    my $index = 0;
    my $hasAuthorOthers = 0;
    foreach(@{$authorsMeta}) {
        my @currAuthor = @{$_};
        @currAuthor = ($index, $index, "", "Unknown", 0, 0.0, 0, 0.0) unless (scalar @currAuthor == 8);

        my $author = {
            id                => @currAuthor[0],
            color_id          => @currAuthor[1],
            name              => @currAuthor[3],
            tokens            => @currAuthor[4],
            token_proportion  => @currAuthor[5],
            commits           => @currAuthor[6],
            commit_proportion => @currAuthor[7],
            token_percent     => sprintf("%.2f\%", 100.0 * @currAuthor[5]),
            commit_percent    => sprintf("%.2f\%", 100.0 * @currAuthor[7])
        };

        push(@authors, $author) unless $author->{id} >= $authorLimit;
        $hasAuthorOthers = 1 if $author->{id} >= $authorLimit;
        $index++;
    }

    if ($hasAuthorOthers == 1) {
        my @authorOther;
        if ('f' eq $type) {
            $result = $fileAuthorOthersSth->execute($bindingVar, $bindingVar, $bindingVar);
            @authorOther = $fileAuthorOthersSth->fetchrow();
        } elsif ('d' eq $type) {
            $result = $subDirAuthorOthersSth->execute($bindingVar, $bindingVar, $bindingVar);
            @authorOther = $subDirAuthorOthersSth->fetchrow();
        }

        if (!defined($result) or scalar(@authorOther) != 7) {
            Warning("Unable to retrieve author Others for [$contentPath]");
            @authorOther = (60, "Black", "Others", 0, 0.0, 0, 0.0);
        }

        push (@authors, {
            id                => @authorOther[0],
            color_id          => @authorOther[1],
            name              => @authorOther[2],
            tokens            => @authorOther[3],
            token_proportion  => @authorOther[4],
            commits           => @authorOther[5],
            commit_proportion => @authorOther[6],
            token_percent     => sprintf("%.2f\%", 100.0 * @authorOther[4]),
            commit_percent    => sprintf("%.2f\%", 100.0 * @authorOther[6])
        });
    }

    FETCHFILESTATS:
    my @statsMeta;
    if ('f' eq $type) {
        $result = $fileTokenCountSth->execute($bindingVar);
        @statsMeta = $fileTokenCountSth->fetchrow();
    } elsif ('d' eq $type) {
        $result = $subDirTokenCountSth->execute($bindingVar);
        @statsMeta = $subDirTokenCountSth->fetchrow();
    }

    if (! defined $result or scalar(@statsMeta) != 1) {
        Warning("Unable to retrieve stats for [$contentPath]");
        @statsMeta = (0);
    }

    $stats->{tokens} = @statsMeta[0];
    $stats->{author_counts} = $authorCount;

    return ([@authors], $stats);
}

sub get_content_dategroup {
    my $contentPath = shift @_;
    my $type = shift @_;

    my @dateGroups = ();
    my $bindingVar;
    my $result;
    my $dategroupMeta;

    if ('f' eq $type) {
        $bindingVar = $contentPath;

        $result = $fileDateGroupSth->execute($bindingVar);
        $dategroupMeta = $fileDateGroupSth->fetchall_arrayref;
    } elsif ('d' eq $type) {
        $bindingVar = ($contentPath eq "root") ? "%" : substr($contentPath, 5)."/%";

        $result = $subDirDateGroupSth->execute($bindingVar);
        $dategroupMeta = $subDirDateGroupSth->fetchall_arrayref;
    }

    if (! defined $result) {
        Warning("Unable to retrieve dategroup for [$contentPath]");
        return ();
    }

    my $lastGroup;
    my $index = 0;
    my $OthersTokenCount = 0;
    foreach (@{$dategroupMeta}) {
        my @currDategroup = @{$_};
        @currDategroup = ("1970-01-01 00:00:00", 60, 0) unless (scalar @currDategroup == 3);

        my $dategroup = str2time(@currDategroup[0]);
        my $authorId = @currDategroup[1];
        my $tokenCount = @currDategroup[2];

        if (! defined $lastGroup) {
            push(@dateGroups, {
                timestr      => time2str("%B %Y", $dategroup),
                timestamp    => $dategroup,
                group        => undef,
                total_tokens => 0
            });
        } elsif ($dategroup != $lastGroup) {
            push(@dateGroups, {
                timestr      => time2str("%B %Y", $dategroup),
                timestamp    => $dategroup,
                group        => undef,
                total_tokens => 0
            });

            if ($OthersTokenCount > 0) {
                push(@{@dateGroups[$index]->{group}}, {
                    author_id   => $authorLimit,
                    token_count => $OthersTokenCount
                });
                $OthersTokenCount = 0;
            }

            $index++;
        }
        @dateGroups[$index]->{total_tokens} += $tokenCount;

        if ($authorId >= $authorLimit) {
            $OthersTokenCount += $tokenCount;
        } else {
            push(@{@dateGroups[$index]->{group}}, {
                author_id   => $authorId,
                token_count => $tokenCount
            });
        }

        $lastGroup = $dategroup;
    }

    if ($OthersTokenCount > 0) {
        push(@{@dateGroups[$index]->{group}}, {
            author_id   => $authorLimit,
            token_count => $OthersTokenCount
        });
    }

    return [@dateGroups];
}

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

# min max time for html date slider
sub get_minmax_time {
    my $dirPath = shift @_;
    my $bindingVar = ($dirPath eq "root") ? "%" : substr($dirPath, 5)."/%";

    my $result;
    my @row;
    my $mintime;
    my $maxtime;

    $result = $minTimeSth->execute($bindingVar);
    @row = $minTimeSth->fetchrow();

    if (! defined($result) or scalar(@row) != 1) {
        Warning("Unable to retrieve mintime for directory [$dirPath]");
        @row = ("1970-01-01 00:00:00");
    }

    $mintime = str2time(@row[0]);

    $result = $maxTimeSth->execute($bindingVar);
    @row = $maxTimeSth->fetchrow();

    if (! defined($result) or scalar(@row) != 1) {
        Warning("Unable to retrieve maxtime for directory [$dirPath]");
        @row = ("2038-01-01 00:00:00");
    }

    $maxtime = str2time(@row[0]);

    return ($mintime, $maxtime);
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
    print "Updating per file activity table and date group table..";
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
    $dbh->do("DROP TABLE IF EXISTS $dategroupTable;");
    $dbh->do(
        "CREATE TABLE $dategroupTable (
        filename text,
        dategroup text,
        personid text,
        personname text,
        tokens int);"
    );
    # perfileactivity table : filename|personid|personname|originalcid|tokens in this commit|autdate
    $dbh->do(
        "WITH t1 AS (SELECT filename, cid, COUNT(cid) AS tokenspercid FROM blametoken
        GROUP BY filename, cid) INSERT INTO $perFileActivityTable SELECT filename,
        personid, COALESCE(personname, 'Unknown'), originalcid, tokenspercid AS tokens,
        autdate FROM t1 LEFT JOIN commits ON (t1.cid=commits.cid) LEFT JOIN commitmap
        ON (t1.cid=commitmap.cid) LEFT JOIN emails ON (autname=emailname AND autemail
        =emailaddr) LEFT JOIN persons USING (personid) ORDER BY filename, tokens DESC;"
    );
    $dbh->do(
        "WITH t1 AS (SELECT *, SUBSTR(autdate, 1, 7)||'-01 00:00:00' AS dategroup FROM
        $perFileActivityTable) INSERT INTO $dategroupTable SELECT filename, t1.dategroup
        AS dategroup, personid, personname, SUM(tokens) AS tokens FROM t1 GROUP BY filename,
        t1.dategroup, personid ORDER BY filename, dategroup;"
    );
    print ".Done!\n";
}

sub create_directory_table_dbi {
    my $dirPath = shift @_;
    my $bindingVar = ($dirPath eq "root") ? "\'%\'" : "\'".substr($dirPath, 5)."/%\'";

    $dbh->do("DROP TABLE IF EXISTS $directoryTmpTable;");
    print "Creating directory data [$dirPath]..";
    $dbh->do(
        "CREATE TABLE $directoryTmpTable AS SELECT personid, personname, SUM(tokens)
        AS tokens, COALESCE(CAST(SUM(tokens) AS float) / NULLIF(CAST((SELECT SUM(tokens) FROM
        $perFileActivityTable WHERE filename LIKE $bindingVar) AS float) , 0), 0) AS token_proportion, COUNT(
        DISTINCT originalcid) AS commits, COALESCE( CAST(COUNT(DISTINCT originalcid) AS float)
        / NULLIF(CAST((SELECT COUNT( DISTINCT originalcid) FROM $perFileActivityTable WHERE filename LIKE $bindingVar)
        AS float), 0), 0) AS commit_proportion FROM $perFileActivityTable WHERE filename LIKE $bindingVar GROUP
        BY personid ORDER BY tokens DESC;"
    ); # personid|personname|tokens|token_proportion|commits|commit_proportion

    prepare_dbi();

    print ".Done!\n";
}

sub prepare_dbi {
    $dirAuthorsSth = $dbh->prepare(
        "SELECT rowid-1 AS id, rowid-1 AS color_id, * FROM $directoryTmpTable;"
    ); # id|color_id|personid|personname|tokens|token_proportion|commits|commit_proportion
    $dirAuthorOthersSth = $dbh->prepare(
        "SELECT $authorLimit AS id, 'Black' AS color_id, 'Others' AS personname, SUM(tokens) AS tokens,
        SUM (token_proportion) AS token_proportion, SUM(commits) AS commits, SUM(commit_proportion) AS
        commit_proportion FROM $directoryTmpTable WHERE rowid > $authorLimit;"
    );
    $dirCommitAndTokenCountSth = $dbh->prepare(
        "SELECT SUM(commits) AS commit_count, SUM(tokens) AS token_counts FROM $directoryTmpTable;"
    );

    $subDirAuthorsSth = $dbh->prepare(
        "WITH t1 AS (SELECT personid, personname, SUM(tokens) AS tokens, COALESCE(CAST(SUM(tokens) AS float)
        / NULLIF(CAST((SELECT SUM(tokens) FROM $perFileActivityTable WHERE filename LIKE ?) AS float) , 0), 0) AS
        token_proportion, COUNT(DISTINCT originalcid) AS commits, COALESCE( CAST(COUNT(DISTINCT originalcid)
        AS float) / NULLIF(CAST((SELECT COUNT( DISTINCT originalcid) FROM $perFileActivityTable WHERE filename LIKE
        ?)AS float), 0), 0) AS commit_proportion FROM $perFileActivityTable WHERE filename LIKE ? GROUP BY personid
        ORDER BY tokens DESC) SELECT $directoryTmpTable.rowid-1 AS id, $directoryTmpTable.rowid-1 AS color_id,
        t1.* FROM t1 INNER JOIN $directoryTmpTable ON (t1.personid = $directoryTmpTable.personid) ORDER BY t1.tokens DESC;"
    ); # id|color_id|personid|personname|tokens|token_proportion|commits|commit_proportion
    $subDirAuthorOthersSth = $dbh->prepare(
        "WITH t1 AS (SELECT personid, personname, SUM(tokens) AS tokens, COALESCE(CAST(SUM(tokens) AS float)
        / NULLIF(CAST((SELECT SUM(tokens) FROM $perFileActivityTable WHERE filename LIKE ?) AS float) , 0), 0) AS
        token_proportion, COUNT(DISTINCT originalcid) AS commits, COALESCE( CAST(COUNT(DISTINCT originalcid)
        AS float) / NULLIF(CAST((SELECT COUNT( DISTINCT originalcid) FROM $perFileActivityTable WHERE filename LIKE
        ?)AS float), 0), 0) AS commit_proportion FROM $perFileActivityTable WHERE filename LIKE ? GROUP BY personid
        ORDER BY tokens DESC) SELECT $authorLimit AS id, 'Black' AS color_id, 'Others' AS personname, SUM(t1.tokens)
        AS tokens, SUM (t1.token_proportion) AS token_proportion, SUM(t1.commits) AS commits, SUM(t1.commit_proportion) AS
        commit_proportion FROM t1 INNER JOIN $directoryTmpTable ON (t1.personid = $directoryTmpTable.personid)
        WHERE $directoryTmpTable.rowid > $authorLimit;"
    ); # id|color_id|personname|tokens|token_proportion|commits|commit_proportion
    $subDirTokenCountSth = $dbh->prepare(
        "SELECT SUM(tokens) AS token_count FROM $perFileActivityTable WHERE filename LIKE ?;"
    );

    $subDirDateGroupSth = $dbh->prepare(
        "SELECT t1.dategroup, t2.rowid-1 AS id, SUM(t1.tokens) AS tokens FROM $dategroupTable AS t1 INNER JOIN
        $directoryTmpTable AS t2 ON(t1.personid=t2.personid) WHERE filename LIKE ? GROUP BY t1.dategroup, t1.personid
        ORDER BY t1.dategroup;"
    );

    $fileAuthorsSth = $dbh->prepare(
        "WITH t1 AS (SELECT personid, personname, SUM(tokens) AS tokens, COALESCE(CAST(SUM(tokens) AS float)
        / NULLIF(CAST((SELECT SUM(tokens) FROM $perFileActivityTable WHERE filename = ?) AS float) , 0), 0) AS
        token_proportion, COUNT(DISTINCT originalcid) AS commits, COALESCE( CAST(COUNT(DISTINCT originalcid)
        AS float) / NULLIF(CAST((SELECT COUNT( DISTINCT originalcid) FROM $perFileActivityTable WHERE filename =
        ?)AS float), 0), 0) AS commit_proportion FROM $perFileActivityTable WHERE filename = ? GROUP BY personid
        ORDER BY tokens DESC) SELECT $directoryTmpTable.rowid-1 AS id, $directoryTmpTable.rowid-1 AS color_id,
        t1.* FROM t1 INNER JOIN $directoryTmpTable ON (t1.personid = $directoryTmpTable.personid) ORDER BY t1.tokens DESC;"
    ); # id|color_id|personid|personname|tokens|token_proportion|commits|commit_proportion
    $fileAuthorOthersSth = $dbh->prepare(
        "WITH t1 AS (SELECT personid, personname, SUM(tokens) AS tokens, COALESCE(CAST(SUM(tokens) AS float)
        / NULLIF(CAST((SELECT SUM(tokens) FROM $perFileActivityTable WHERE filename = ?) AS float) , 0), 0) AS
        token_proportion, COUNT(DISTINCT originalcid) AS commits, COALESCE( CAST(COUNT(DISTINCT originalcid)
        AS float) / NULLIF(CAST((SELECT COUNT( DISTINCT originalcid) FROM $perFileActivityTable WHERE filename =
        ?)AS float), 0), 0) AS commit_proportion FROM $perFileActivityTable WHERE filename = ? GROUP BY personid
        ORDER BY tokens DESC) SELECT $authorLimit AS id, 'Black' AS color_id, 'Others' AS personname, SUM(t1.tokens)
        AS tokens, SUM (t1.token_proportion) AS token_proportion, SUM(t1.commits) AS commits, SUM(t1.commit_proportion) AS
        commit_proportion FROM t1 INNER JOIN $directoryTmpTable ON (t1.personid = $directoryTmpTable.personid)
        WHERE $directoryTmpTable.rowid > $authorLimit;"
    ); # id|color_id|personname|tokens|token_proportion|commits|commit_proportion
    $fileTokenCountSth = $dbh->prepare(
        "SELECT SUM(tokens) AS token_count FROM $perFileActivityTable WHERE filename = ?;"
    );

    $fileDateGroupSth = $dbh->prepare(
        "SELECT t1.dategroup, t2.rowid-1 AS id, SUM(t1.tokens) AS tokens FROM $dategroupTable AS t1 INNER JOIN
        $directoryTmpTable AS t2 ON(t1.personid=t2.personid) WHERE filename = ? GROUP BY t1.dategroup, t1.personid
        ORDER BY t1.dategroup;"
    );

    $minTimeSth = $dbh->prepare(
        "SELECT MIN(autdate) FROM $perFileActivityTable WHERE filename LIKE ?;"
    );
    $maxTimeSth = $dbh->prepare(
        "SELECT MAX(autdate) FROM $perFileActivityTable WHERE filename LIKE ?;"
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
