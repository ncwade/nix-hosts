"""Libation can exit zero after a per-book failure; verify its exported results."""
import json
from pathlib import Path
import re
import sys


def check(inventory, output):
    # These messages come from Libation 14.2.5's ProcessableOptionsBase.
    if re.search(r'Error processing book\.|CLI error\.|Not attempting this title again', output):
        raise ValueError('Libation reported an individual download failure')
    owned = [b for b in inventory if not b['IsAudiblePlus'] and not b['AbsentFromLastScan']
             and b['ContentType'] == 'Product']
    pending = [b for b in owned if b['BookStatus'] != 'Liberated'
               or (b['HasPdf'] and b['PdfStatus'] != 'Liberated')]
    # The per-run size bound intentionally defers the rest to the next hourly run.
    limited = "Done. Stopped early: this run's download limit was reached." in output
    if pending and not limited:
        raise ValueError(f'{len(pending)} purchased titles still have incomplete audio or companion PDFs')


if __name__ == '__main__':
    try:
        check(json.loads(Path(sys.argv[1]).read_text()), Path(sys.argv[2]).read_text())
    except (ValueError, KeyError, OSError) as error:
        print(f'Audible result verification failed: {error}', file=sys.stderr)
        raise SystemExit(1)
