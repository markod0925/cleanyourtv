package com.gathin.tvhome;

import org.junit.Test;

import static org.junit.Assert.assertEquals;

public class DockOpacityTest {
    @Test public void savedDockChoicesIncludeTwoAndThreeColumns() {
        assertEquals(2, Config.chosenColumns(2, 3));
        assertEquals(3, Config.chosenColumns(3, 4));
        assertEquals(3, Config.chosenColumns(1, 3));
        assertEquals(3, Config.chosenColumns(8, 3));
    }
    @Test public void dockTileTransparencyDoesNotDimOtherTiles() {
        assertEquals(0.8f, AppAdapter.cardOpacity(true, 80), 0f);
        assertEquals(1f, AppAdapter.cardOpacity(false, 80), 0f);
        assertEquals(0f, AppAdapter.cardOpacity(true, -1), 0f);
        assertEquals(1f, AppAdapter.cardOpacity(true, 101), 0f);
    }
    @Test public void aChoiceMadeOnTheTvWinsOverTheTheme() {
        // Theme says 80, the owner picked 30 in Launcher settings.
        assertEquals(30, Config.chosenDockOpacity(30, 80));
        assertEquals(100, Config.chosenDockOpacity(100, 80));
    }

    @Test public void noChoiceKeepsTheThemeValue() {
        // -1 is what Config passes when nothing is saved (or a theme push cleared it).
        assertEquals(80, Config.chosenDockOpacity(-1, 80));
    }

    @Test public void anOutOfRangeChoiceIsIgnored() {
        // Below 30 the band would vanish and the dock lose its shape; the theme key has the same floor.
        assertEquals(80, Config.chosenDockOpacity(0, 80));
        assertEquals(80, Config.chosenDockOpacity(29, 80));
        assertEquals(80, Config.chosenDockOpacity(101, 80));
    }
}
