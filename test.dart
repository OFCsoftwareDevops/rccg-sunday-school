


@override
Widget build(BuildContext context) {
  final screenHeight = MediaQuery.of(context).size.height;
  final popupHeight = screenHeight * widget.heightFraction;
  final theme = Theme.of(context);
  final lineHeight = context.lineHeight;

  return Container(
    height: popupHeight,
    width: double.infinity,
    decoration: BoxDecoration(
      color: theme.colorScheme.background,
      borderRadius: BorderRadius.vertical(top: Radius.circular(16.sp)),
    ),
    child: Stack(
      children: [
        // Main content
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 20.sp),
          child: Column(
            children: [
              SizedBox(height: 16.sp),

              // Header row
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      widget.reference,
                      style: TextStyle(
                        fontSize: 17.sp,
                        fontWeight: FontWeight.bold,
                        color: AppColors.scriptureHighlight,
                      ),
                    ),
                  ),
                  // ← The new link/button
                  GestureDetector(
                    onTap: _openFullChapter,
                    child: Padding(
                      padding: EdgeInsets.only(top: 4.sp),
                      child: Text(
                        "Open full chapter →",
                        style: TextStyle(
                          fontSize: 14.sp,
                          color: theme.colorScheme.onBackground,
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ),
                  SmartSaveReadingButton(
                    ref: widget.reference,
                    todayReading: widget.reference,
                  ),
                  if (widget.showCloseButton)
                    IconButton(
                      icon: Icon(
                        Icons.close_rounded,
                        size: 24.sp,
                        color: theme.colorScheme.onBackground.withOpacity(0.7),
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () async {
                        await AnalyticsService.logButtonClick('further_reading_canceled');
                        Navigator.of(context).pop();
                        Future.delayed(const Duration(milliseconds: 80), () {
                          while (Navigator.of(context).canPop()) {
                            Navigator.of(context).pop();
                          }
                        });
                      },
                      tooltip: 'Close',
                    ),
                ],
              ),

              SizedBox(height: 12.sp),

              Expanded(
                child: Scrollbar(
                  thickness: 4.sp,
                  radius: const Radius.circular(10),
                  thumbVisibility: true,
                  child: ListView.builder(
                    physics: const BouncingScrollPhysics(),
                    padding: EdgeInsets.only(right: 10.sp, bottom: 120.sp), // extra space for floating button
                    itemCount: widget.verses.length,
                    itemBuilder: (context, index) {
                      // ... your existing verse item code ...
                    },
                  ),
                ),
              ),
            ],
          ),
        ),

        // Overlay Action Sheet
        if (_selectedVerses.isNotEmpty)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: VerseActionSheet(
              bookName: widget.bookName ?? _extractBookNameFromReference(widget.reference),
              chapter: widget.chapterNum ?? _extractChapterFromReference(widget.reference),
              verses: _selectedVerses.toList()..sort(),
              versesText: {
                for (final verseMap in widget.verses)
                  (verseMap['verse'] as int): verseMap['text'] as String,
              },
            ),
          ),
      ],
    ),
  );
}