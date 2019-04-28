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
    var $contributor_header_row = $("#overall-tats-table > thead > tr");
    var $contributor_headers = $("#overall-stats-table > thead > tr > th");
    var $contributor_footers = $("#overall-stats-table > tfoot > tr > td");
    var $contributor_row_container = $("#overall-stats-table > tbody");
    var $content = $('#content-view');
    var $mainContent = $("#main-content");
    var $dateGradient = $("#date-gradient");
    var $dateSliderRange = $("#date-slider-range");
    var $statsGraphButton = $("button.content-stats-graph");
    var $absPropToggle = $("#abs-prop-toggle");
    var $hideSubDirButton = $("#hide-subdirectory-btn");
    var $graphTableData = $(".graph-table-data");
    var $expandableTables = $("table.expandable");
    var $statsTableExpandableButton = $("button.expand-collapse-table-btn");
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

    function SetupAgeColors() {
        var base = timeMin;
        var range = timeRange;

        function convert(color) {
            var canvas = document.createElement("canvas");
            var context = canvas.getContext("2d");
            context.fillStyle = color;
            return parseInt(context.fillStyle.substr(1), 16);
        }

        function lerp(c1, c2, t) {
            var r = (c1 & 0xFF0000) * (1 - t) + (c2 & 0xFF0000) * t;
            var g = (c1 & 0x00FF00) * (1 - t) + (c2 & 0x00FF00) * t;
            var b = (c1 & 0x0000FF) * (1 - t) + (c2 & 0x0000FF) * t;
            return (r & 0xFF0000) | (g & 0x00FF00) | (b & 0x0000FF);
        }

        var root = $(":root");
        var ageOld = convert(root.css("--age-old"));
        var ageMid = convert(root.css("--age-mid"));
        var ageNew = convert(root.css("--age-new"));

        $spans.children(".age-highlighting").each(function() {
            var ageSpan = $(this);
            var t = (ageSpan.data("timestamp")-base) / range;
            var color = (t < 0.5 ? lerp(ageOld, ageMid, t/0.5) : lerp(ageMid, ageNew, (t - 0.5) / 0.5));
            var htmlColor = "#" + ("000000" + color.toString(16)).substr(-6);

            this.style.setProperty('--age-color', htmlColor);
        });

        ageSetupDone = true;
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
            rows.push($("<tr class='contributor-row'><td>&nbsp</td><td/><td/><td/><td/><td/></tr>").get(0));

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
    }

    function AuthorLabel_Click(event)
    {
        event.stopPropagation();

        var authorId = this.dataset.authorid;
        highlightMode = 'author-single';
        selectedAuthorId = authorId;

        var elem = $highlightSelect.get(0);
        var options = elem.options;
        var option = options.namedItem(authorId);

        guiUpdate = true;
        elem.selectedIndex = option.index;
        guiUpdate = false;

        $dateGradient.addClass("invisible");

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
            $fixedHeader.find("button").text($absPropToggle.text());
            var text = $absPropToggle.attr("title") ? $absPropToggle.attr("title") : "";
            $fixedHeader.find("button").prop("title", text);
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

    function BindExpandButton() {
        $statsTableExpandableButton = $("button.expand-collapse-table-btn");

        $statsTableExpandableButton.click(function() {
            var isExpandBtn = $(this).hasClass("expand");
            if (isExpandBtn) {
                $(this).parents("tr").siblings(".hidden").each(function() {
                    $(this).removeClass("hidden");
                });
                $(this).html("click to collapse&#x25b2;");
            } else {
                $(this).parents("tbody").children("tr.contributor-row").each(function(i){
                    if (20 > i) { return; }

                    $(this).addClass("hidden");
                });
                $(this).html("click to expand&#x25bc;");
            }
            $(this).toggleClass("expand collapse");
            RenderMinimap();
        });
    }

    $statsGraphButton.click(StatsGraph_Click);

    $fixedHeader.find("button").click(function() {
        $absPropToggle.trigger("click");
        $fixedHeader.find("button").text($absPropToggle.text());
        $fixedHeader.find("button").prop("title", $absPropToggle.attr("title"));
    });

    $graphTableData.mouseenter(function() {
        if ($absPropToggle.hasClass("active")) { return; }
        $(this).children().addClass("full-scale");
    });

    $graphTableData.mouseleave(function() {
        if ($absPropToggle.hasClass("active")) { return; }
        $(this).children().removeClass("full-scale");
    });

    $expandableTables.each(function() {
        CollapseTables($(this), 20);
    });

    BindExpandButton();

    $contributor_headers.click(ColumnHeader_Click);

    $("#date-from").change(DateInput_Changed);
    $("#date-to").change(DateInput_Changed);

    UpdateDate();

    $("#date-from").get(0).valueAsDate = dateFrom;
    $("#date-to").get(0).valueAsDate = dateTo;

    $(".table-author").click(AuthorLabel_Click);

    $dateSliderRange.slider({range: true, min: 0, max: timeRange, values: [ 0, timeRange ], slide: DateSlider_Changed });

    $minimap.mousedown(Minimap_MouseDown);
    $document.mousemove(Document_MouseMove);
    $document.mouseup(Document_MouseUp);
    $document.bind("selectstart", null, Document_SelectStart);

    $mainContent.scroll(Window_Scroll);
    $window.resize(Debounce(Window_Resize, 250));

    UpdateMinimapViewSize();
    RenderMinimap();

    SetupAgeColors();
});
