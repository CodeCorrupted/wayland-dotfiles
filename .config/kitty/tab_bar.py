import subprocess
from datetime import datetime
from typing import List, Tuple

from kitty.fast_data_types import Screen, get_options
from kitty.utils import color_as_int

from kitty.tab_bar import DrawData, ExtraData, TabBarData, as_rgb

translate_map = str.maketrans({"~": " "})


def get_title(tab: TabBarData, max_title_length, username) -> str:
  title = tab.title.translate(translate_map) if tab.title != "~" else f" {username}"
  if title.startswith("/"):
      title = "󰉉 " + title
  if len(title) > max_title_length:
      title = title[: max_title_length - 3] + "•••"
  return f" {title} "


class GhostBar:
  def __init__(self) -> None:
      opts = get_options()
      self.username = subprocess.run(
          ["whoami"], capture_output=True, text=True
      ).stdout.strip()

      self.left_length = len(f"󰣇 {self.username} ")
      self.right_length = 0
      self.tabs: List[TabBarData] = []

      self.default_state = (
          as_rgb(color_as_int(opts.foreground)),
          as_rgb(color_as_int(opts.background)),
      )
      self.inactive_tab_fg: int = as_rgb(color_as_int(opts.active_tab_foreground))
      self.inactive_tab_bg: int = as_rgb(color_as_int(opts.active_tab_background))
      self.active_tab_bg: int = as_rgb(color_as_int(opts.color4))
      self.active_tab_fg: int = as_rgb(color_as_int(opts.background))
      self.tab_bar_fg: int = as_rgb(color_as_int(opts.inactive_tab_foreground))
      self.tab_bar_bg: int = as_rgb(color_as_int(opts.background))

  def _get_state(self, screen: Screen) -> Tuple[int, int]:
      return (screen.cursor.fg, screen.cursor.bg)

  def set_state(self, screen: Screen, state: Tuple[int, int]) -> None:
      screen.cursor.fg = state[0]
      screen.cursor.bg = state[1]

  def draw_left(self, screen: Screen) -> int:
      state = self._get_state(screen)
      screen.cursor.bold = True
      screen.cursor.italic = False
      screen.cursor.x = 0

      self.set_state(screen, (self.inactive_tab_fg, self.inactive_tab_bg))
      screen.draw(f"󰣇 {self.username} ")
      self.set_state(screen, (self.inactive_tab_bg, state[1]))
      screen.draw("")

      self.set_state(screen, state)
      return screen.cursor.x

  def draw_center(
      self,
      draw_data: DrawData,
      screen: Screen,
      cur_tab: TabBarData,
      before: int,
      max_title_length: int,
      cur_index: int,
      is_last: bool,
      extra_data: ExtraData,
  ) -> int:
      state = self._get_state(screen)
      screen.cursor.bold = True

      self.tabs.append(cur_tab)
      if is_last:
          active_tab_index = next(i for i, x in enumerate(self.tabs) if x.is_active)
          center = "   ".join(
              get_title(x, max_title_length, self.username) for x in self.tabs
          )
          self.center_length = len(center) + 2
          screen.cursor.x = screen.columns // 2 - self.center_length // 2

          def draw_active(index: int, tab: TabBarData):
              screen.cursor.italic = False
              self.set_state(
                  screen,
                  (
                      self.active_tab_bg,
                      self.inactive_tab_bg
                      if len(self.tabs) > 1 and index != 0
                      else self.tab_bar_bg,
                  ),
              )
              screen.draw("")
              self.set_state(screen, (self.active_tab_fg, self.active_tab_bg))
              screen.draw(get_title(tab, max_title_length, self.username))
              self.set_state(
                  screen,
                  (
                      self.active_tab_bg,
                      self.inactive_tab_bg
                      if len(self.tabs) > 1 and index != len(self.tabs) - 1
                      else self.tab_bar_bg,
                  ),
              )
              screen.draw("")
              self.set_state(screen, (self.inactive_tab_fg, self.inactive_tab_bg))
              screen.cursor.italic = False

          for index, tab in enumerate(self.tabs):
              screen.cursor.bold = False
              if tab.is_active:
                  screen.cursor.bold = True
                  draw_active(index, tab)
                  continue
              elif index == 0:
                  self.set_state(screen, (self.inactive_tab_bg, self.tab_bar_bg))
                  screen.draw("")
                  self.set_state(screen, (self.inactive_tab_fg, self.inactive_tab_bg))
                  screen.cursor.italic = False
                  screen.draw(get_title(tab, max_title_length, self.username))
              elif index == cur_index - 1:
                  screen.cursor.italic = False
                  screen.draw(get_title(tab, max_title_length, self.username))
                  self.set_state(screen, (self.inactive_tab_bg, self.tab_bar_bg))
                  screen.draw("")
                  break
              else:
                  screen.cursor.italic = False
                  screen.draw(get_title(tab, max_title_length, self.username))
              screen.draw(
                  ""
                  if index > active_tab_index
                  else ("" if index != active_tab_index - 1 else "")
              )

      self.set_state(screen, state)
      return screen.cursor.x

  def draw_right(self, screen: Screen) -> int:
      state = self._get_state(screen)
      screen.cursor.bold = True
      screen.cursor.italic = False

      self.right_length = len(f"{datetime.now().strftime('  %I:%M %p')}")
      screen.cursor.x = screen.columns - self.right_length

      self.set_state(screen, (self.inactive_tab_bg, state[1]))
      screen.draw("")
      self.set_state(screen, (self.inactive_tab_fg, self.inactive_tab_bg))
      screen.draw(datetime.now().strftime("  %I:%M %p"))

      self.set_state(screen, state)
      return screen.cursor.x

  def draw_tab(
      self,
      draw_data: DrawData,
      screen: Screen,
      tab: TabBarData,
      before: int,
      max_title_length: int,
      index: int,
      is_last: bool,
      extra_data: ExtraData,
  ) -> int:
      self.set_state(screen, (self.tab_bar_fg, self.tab_bar_bg))
      screen.cursor.bold = True

      if index == 1:
          screen.draw(" " * screen.columns)
          self.tabs = []
          self.draw_left(screen)

      self.draw_center(
          draw_data, screen, tab, before, max_title_length, index, is_last, extra_data
      )

      if is_last:
          self.draw_right(screen)
      return screen.cursor.x


bar = GhostBar()


def draw_tab(*args) -> int:
  return bar.draw_tab(*args)
