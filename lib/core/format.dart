String _two(int n) => n.toString().padLeft(2, '0');

String formatDate(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';

String formatDateTime(DateTime d) =>
    '${d.year}/${_two(d.month)}/${_two(d.day)}  ${_two(d.hour)}:${_two(d.minute)}';
