$(document).ready(function() {
    var timeRange;
    var dateFrom = new Date(timeMin * 1000);
    var dateTo = new Date(timeMax * 1000);
    var spanGroupData = undefined;

    var guiUpdate = false;
    var sortColumn = 3; // contributor table default order
    var sortReverse = false;
    var scrollDrag = false;
    var dateChanged = true;

    var $window = $(window);
    var $document = $(document);
    var $minimap = $('#minimap');
    var $spans = $('.content-stats-graph');
    var $minimapView = $('#minimap-view-shade,#minimap-view-frame');
    var $contributor_rows = $("#overall-stats-table > tbody > tr.contributor-row");
    var $contributor_headers = $("#overall-stats-table > thead > tr > th");
    var $contributor_row_container = $("#overall-stats-table > tbody");
    var $content = $('#content-view');
    var $mainContent = $("#main-content");
    var $dateSliderRange = $("#date-slider-range");
    var $statsGraphButton = $("button.content-stats-graph");
    var $tokenAuthorToggle = $("#token-author-toggle");
    var $graphTableData = $(".graph-table-data");
    var $expandableTables = $("table.expandable");
    var $genderGroupsByTokens = $(".gender-by-tokens");
    var $genderGroupsByAuthors = $(".gender-by-authors");
    var $contentListHeader = $("#content-list-header");
    var $fixedHeader = $contentListHeader.clone();
    $fixedHeader.addClass("content-list-header-fixed");
    $fixedHeader.hide();
    $contentListHeader.after($fixedHeader);


    // Processes large jquery objects in slices of N=length at rest intervals of I=interval (ms)
    function ProcessSlices(jquery, length, interval, fn)
    {
        clearTimeout(this.slicesCallback);
        this.slicesCallback = undefined;
        if (jquery.length == 0) // if no element in the jquery object: return
            return;

        var context = this;
        var cur = jquery.slice(0, length); // reduce the set of elements
        var next = jquery.slice(length);
        cur.each(fn);

        this.slicesCallback = setTimeout(function() { ProcessSlices(next, length, interval, fn); }, interval);
    }

    // Filter callback invocations until no invocations have been made for T=timeout (ms)
    function Debounce(fn, timeout)
    {
        var callback;
        return function() {
            var context = this;
            var args = arguments;
            var doNow = function() {
                fn.apply(context, args);
                callback = undefined;
            };
            clearTimeout(callback);
            callback = setTimeout(doNow, timeout);
        };
    }

    function ApplyHighlight() {
        var authorGender;
        function groupMatch(dateGroup) {
            var timestamp = dateGroup.timestamp;
            var group = dateGroup.group;
            var date = new Date(timestamp * 1000);

            var dateOkay = date >= dateFrom && date <= dateTo;
            var genderOkay = group.find(function(genderStats) {
                return genderStats.gender === authorGender;
            });

            return dateOkay && (undefined != genderOkay);
        }

        function getTotalStatsInPeriod() {
            var matchedGroup = spanGroupData.filter(function(dateGroup) {
                var timestamp = dateGroup.timestamp;
                var date = new Date(timestamp * 1000);

                return date >= dateFrom && date <= dateTo;
            });

            const authorSet = new Set();

            var tokenCounts = 0;
            matchedGroup.forEach(function(dateGroup) {
                tokenCounts += dateGroup.total_tokens;
                authorSet.add(dateGroup.author_id);
            });

            return [tokenCounts, authorSet.size];
        }

        function getGenderSpanStats(jquery) {
            authorGender = jquery.data("gender");

            var tokenCount = 0;
            const authorSet = new Set();
            var matchedGroup = spanGroupData.filter(groupMatch);
            matchedGroup.forEach(function (dateGroup) {
                dateGroup.group.forEach(function(genderStats) {
                    if (genderStats.gender === authorGender) {
                        tokenCount += genderStats.token_count;
                        authorSet.add(genderStats.author_id);
                    }
                });
            });

            return [tokenCount, authorSet.size];
        }

        var dataScript = $(this).children("#data-script");
        if (dateChanged) { eval(dataScript.html()); }

        var gender;
        var authorCount;
        var tokenCount;
        var stats = getTotalStatsInPeriod();
        var totalTokens = stats[0];
        var totalAuthors = stats[1];
        var spanGroup;

        if ($tokenAuthorToggle.hasClass("token-toggle")) {
            // token distribution
            spanGroup = $(this).children(".gender-by-tokens");

            spanGroup.each(function () {
                var colorSpan = $(this);
                gender = colorSpan.data("gender");
                tokenCount = getGenderSpanStats(colorSpan)[0];

                var newPercentage = (totalTokens === 0) ? 0 : 100*tokenCount/totalTokens;
                colorSpan.css("width", newPercentage+"%");
                var genderText = colorSpan.text();
                colorSpan.prop("title", genderText+" : "+tokenCount+" token(s) and "+newPercentage.toFixed(2)+"% of token contributions");
            });
        } else if ($tokenAuthorToggle.hasClass("author-toggle")) {
            // author distribution
            spanGroup = $(this).children(".gender-by-authors");

            spanGroup.each(function () {
                var colorSpan = $(this);
                gender = colorSpan.data("gender");
                authorCount = getGenderSpanStats(colorSpan)[1];

                var newPercentage = (totalAuthors === 0) ? 0 : 100*authorCount/totalAuthors;
                colorSpan.css("width", newPercentage+"%");
                var genderText = colorSpan.text();
                colorSpan.prop("title", genderText+" : "+authorCount+" author(s) and "+newPercentage.toFixed(2)+"% of author distribution");
            });
        }
    }

    function UpdateHighlight() {
        $spans.each(ApplyHighlight);
        RenderMinimap();
    }

    function RenderMinimap() {
        var canvas = document.getElementById("minimap-image");
        canvas.width = $(canvas).width();
        canvas.height = $(canvas).height();

        var ctx = canvas.getContext("2d");
        ctx.clearRect(0, 0, canvas.width, canvas.height);
        ctx.setTransform(canvas.width / $content.width(), 0, 0, canvas.height / $content.height(), 0, 0);

        // check if current page needs minimap
        var scrollVisible = $mainContent.get(0).scrollHeight > $mainContent.get(0).clientHeight;
        if (!scrollVisible) {
            $minimapView.addClass("hidden");
            return;
        }
        $minimapView.removeClass("hidden");

        var unitX = $content.width() / canvas.width;
        var tabSize = $content.css("tab-size");
        var content = $content.get(0);
        var base = $(content).offset();
        var baseTop = base.top;
        var baseLeft = base.left;
        ProcessSlices($spans, 500, 50, function(i, span) {
            var s = $(span);
            if (s.is(":hidden"))
                return;

            var x = s.offset();
            var startTop = x.top - baseTop;
            var startLeft = 0;
            var lineHeight = 15;
            var left = startLeft;

            ctx.font = $content.css("font-size") + " " + $content.css("font-family");
            var childrenSpan = s.children();
            childrenSpan.each(function() {
                if ($(this).hasClass("hidden") == true)	{ return; }

                ctx.fillStyle = $(this).css("background-color");
                var width = $(this).width();
                ctx.fillRect(left, startTop, 1.5*width, lineHeight);
                left += 1.5*width;
            });
        });

        UpdateMinimapViewPosition();
        UpdateMinimapViewSize();
    }

    function UpdateMinimapViewPosition()
    {
        var areaY = -$content.position().top;
        var areaHeight = $content.height();
        var mapHeight = $minimap.height();
        var mapYMax = (areaHeight - $mainContent.height()) / areaHeight * mapHeight;
        var mapY = (areaY / areaHeight) * mapHeight;

        $minimapView.css('top', Math.max(0, Math.min(mapY, mapYMax)));
    }

    function UpdateMinimapViewSize()
    {
        var viewHeight = $mainContent.innerHeight();
        var docHeight = $content.height();
        var mapHeight = $minimap.height();
        var mapViewHeightMax = $minimap.height();
        var mapViewHeight = (viewHeight / docHeight) * mapHeight;

        $minimapView.css('height', Math.min(mapViewHeight, mapViewHeightMax));
    }

    function SortContributors(column, reverse)
    {
        var cmp = function(a, b) { if (a < b) return -1; if (a > b) return 1; return 0; };
        var lexical = function (a, b) {
            return a.children[0].firstChild.innerText.localeCompare(b.children[0].firstChild.innerText);
        };
        var numeric = function (a, b) { return cmp(parseFloat(b.children[column].innerHTML), parseFloat(a.children[column].innerHTML)); };
        var numericThenLex = function (a, b) { return numeric(a, b) || lexical(a, b); };


        var $rows = $contributor_rows;
        var rows = $contributor_rows.get();
        rows.forEach(function(x, i) { $(x).removeClass("hidden"); });

        if (column === 0)
            rows.sort(lexical);
        else
            rows.sort(numericThenLex);
        if (reverse)
            rows.reverse();

        // Pad up to 6 rows using the longest name for visual stability.
        while (rows.length < Math.min(6, $rows.length))
            rows.push($("<tr class='contributor-row'><td>&nbsp;</td><td/><td/><td/><td/><td/><td/></tr>").get(0));

        $rows.detach(); // Detach before empty so rows don't get deleted
        $contributor_row_container.children("tr.contributor-row").empty();
        $contributor_row_container.prepend(rows);
    }

    function CollapseTables(jquery, number) {
        var $rows = jquery.children("tbody").children("tr.contributor-row");
        if ($rows.length <= number) { return; }

        $rows.each(function(i) {
            if (number > i) { return; }
            $(this).addClass("hidden");
        });

        var colspan = $rows.get(0).childElementCount;
        $rows.parent().append("<tr><td colspan=\""+colspan+"\" class=\"expand-stats-table\"><button class=\"expand-collapse-table-btn toggle-btn expand\">click to expand&#x25BC;</button></td></tr>");
    }

    function DoMinimapScroll(event)
    {
        var mouseY = event.clientY;
        var minimapY = mouseY - $minimap.offset().top;
        var contentY = minimapY / $minimap.height() * $content.height();
        var scrollY = $content.get(0).offsetTop + contentY;
        var scrollYMid = scrollY - $mainContent.height() / 2;

        $mainContent.scrollTop(scrollYMid);
    }

    function DateInput_Changed()
    {
        if (guiUpdate)
            return;

        dateFrom = document.getElementById("date-from").valueAsDate;
        dateFrom = new Date(dateFrom.getFullYear(), dateFrom.getMonth(), 1, 0, 0, 0);
        dateTo = document.getElementById("date-to").valueAsDate;
        dateTo = new Date(dateTo.getFullYear(), dateTo.getMonth(), 1, 0, 0, 0);

        var timeStart = dateFrom.getTime() / 1000 - timeMin;
        var timeEnd = dateTo.getTime() / 1000 - timeMin;

        guiUpdate = true;
        $dateSliderRange.slider("values", [timeStart, timeEnd]);
        guiUpdate = false;

        dateChanged = true;
        UpdateHighlight();
    }

    function DateSlider_Changed(event, ui)
    {
        if (guiUpdate)
            return;

        var timeStart = timeMin + ui.values[0];
        var timeEnd = timeMin + ui.values[1];
        dateFrom = new Date(timeStart * 1000);
        dateTo = new Date(timeEnd * 1000);

        guiUpdate = true;
        // reformat the dateFrom and dateTo to only allows user to change month and year
        var yearFrom = dateFrom.getFullYear();
        var monthFrom = dateFrom.getMonth();
        dateFrom = new Date(yearFrom, monthFrom, 1, 0, 0, 0);

        var yearTo = dateTo.getFullYear();
        var monthTo = dateTo.getMonth();
        dateTo = new Date(yearTo, monthTo, 1, 0, 0, 0);

        $("#date-from").get(0).valueAsDate = dateFrom;
        $("#date-to").get(0).valueAsDate = dateTo;
        guiUpdate = false;

        dateChanged = true;
        UpdateHighlight();
    }

    function ColumnHeader_Click(event)
    {
        event.stopPropagation();

        var column = Array.prototype.indexOf.call(this.parentNode.children, this);
        sortReverse = !sortReverse && (column == sortColumn);
        sortColumn = column;

        var expandCollapseButton = $(this).parents("table.expandable").find("button.expand-collapse-table-btn");
        expandCollapseButton.trigger("click");
        SortContributors(sortColumn, sortReverse);
        expandCollapseButton.trigger("click");
    }

    function Minimap_MouseDown(event)
    {
        if (event.buttons == 1) {
            scrollDrag = true;
            DoMinimapScroll(event);
        }
    }

    function Document_MouseUp(event)
    {
        if (event.buttons == 1)
            scrollDrag = false;
    }

    function Document_MouseMove(event)
    {
        if (scrollDrag && event.buttons == 1)
            DoMinimapScroll(event);
        else
            scrollDrag = false;
    }

    function Document_SelectStart(event)
    {
        // Disable text selection while dragging the minimap.
        if (scrollDrag)
            event.preventDefault();
    }

    function UpdateContentListHeaderWidth() {
        var height = document.getElementById("content-list-header").offsetTop;
        var width = $(".content-list").last().width();

        if ($mainContent.scrollTop() > height) {
            $fixedHeader.css("width", width*100/$mainContent.innerWidth()+"%");
            $fixedHeader.find("button").text($tokenAuthorToggle.text());
            $fixedHeader.find("button").prop("title", $tokenAuthorToggle.attr("title"));
            $fixedHeader.show();
        }
        if ($mainContent.scrollTop() < height || $mainContent.scrollTop() > $content.height()) {
            $fixedHeader.hide();
        }
    }

    function Window_Scroll()
    {
        UpdateMinimapViewPosition();
        UpdateContentListHeaderWidth();
    }

    function Window_Resize()
    {
        RenderMinimap();
        UpdateContentListHeaderWidth();
    }

    function UpdateDate() {
        var yearFrom = dateFrom.getFullYear();
        var monthFrom = dateFrom.getMonth();
        dateFrom = new Date(yearFrom, monthFrom, 1, 0, 0, 0);
        timeMin = Math.round(dateFrom.getTime()/1000);

        var yearTo = dateTo.getFullYear();
        var monthTo = dateTo.getMonth();
        dateTo = new Date(yearTo, monthTo+1, 1, 0, 0, 0);
        timeMax = Math.round(dateTo.getTime()/1000);

        timeRange = timeMax - timeMin;
    }

    function StatsGraph_Click() {
        var contentGraph = $(this);
        contentDetail = contentGraph.parents(".content-list").next(".constent-stats-table-wrapper");
        contentDetail.slideToggle(400, RenderMinimap);
    }

    function TokenAuthorToggle_Click() {
        if ($(this).hasClass("token-toggle")) {
            $(this).text("authors");

            $genderGroupsByTokens.addClass("hidden");
            $genderGroupsByAuthors.removeClass("hidden");
        } else {
            $(this).text("tokens");
            $genderGroupsByTokens.removeClass("hidden");
            $genderGroupsByAuthors.addClass("hidden");
        }

        $(this).toggleClass("token-toggle author-toggle");
        RenderMinimap();
    }

    $statsGraphButton.click(StatsGraph_Click);

    $tokenAuthorToggle.click(TokenAuthorToggle_Click);
    $fixedHeader.find("button").click(function() {
        $tokenAuthorToggle.trigger("click");
        $fixedHeader.find("button").text($tokenAuthorToggle.text());
        $fixedHeader.find("button").prop("title", $tokenAuthorToggle.attr("title"));
    });

    $expandableTables.each(function() {
        CollapseTables($(this), 20);
    });

    $contributor_headers.click(ColumnHeader_Click);

    $("#date-from").change(DateInput_Changed);
    $("#date-to").change(DateInput_Changed);

    UpdateDate();

    $("#date-from").get(0).valueAsDate = dateFrom;
    $("#date-to").get(0).valueAsDate = dateTo;

    $dateSliderRange.slider({range: true, min: 0, max: timeRange, values: [ 0, timeRange ], slide: DateSlider_Changed });

    $minimap.mousedown(Minimap_MouseDown);
    $document.mousemove(Document_MouseMove);
    $document.mouseup(Document_MouseUp);
    $document.bind("selectstart", null, Document_SelectStart);

    $mainContent.scroll(Window_Scroll);
    $window.resize(Debounce(Window_Resize, 250));

    UpdateMinimapViewSize();
    RenderMinimap();
});
