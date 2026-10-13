from pathlib import Path
project = Path(defines['project'])
format = 'UDZO'
files = [str(project / 'release/flowgpt/FlowGpt.app')]
symlinks = {'Applications': '/Applications'}
background = str(project / 'release/dmg-background.png')
icon_locations = {'FlowGpt.app': (146, 205), 'Applications': (496, 205)}
window_rect = ((200, 160), (640, 480))
icon_size = 96
text_size = 14
default_view = 'icon-view'
show_toolbar = False
show_status_bar = False
show_pathbar = False
show_sidebar = False
arrange_by = None
