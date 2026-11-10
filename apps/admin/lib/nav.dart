/// The tabs of the admin shell, in bottom-bar order.
enum AdminTab { home, jobs, customers, crew }

/// The three views of the Jobs tab, in segmented-control order.
enum JobsView { active, today, history }

/// What the History view of the Jobs tab is narrowed to.
enum HistoryFilter { all, done, cancelled, needsPayment }

/// Switches the shell to [tab]; for the Jobs tab optionally to one of its
/// views and history filters.
typedef GoTo = void Function(AdminTab tab, {JobsView? view, HistoryFilter? filter});
