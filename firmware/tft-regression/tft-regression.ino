// Standalone regression for the constructor and wiring reported working.
// This sketch drives only the display. Do not combine with the terminal's
// current buzzer wiring: GPIO2 is TFT DC in this reference configuration.
#include <SPI.h>
#include <Adafruit_GFX.h>
#include <Adafruit_ILI9341.h>

Adafruit_ILI9341 tft(5, 2, 23, 18, 4, 19);

void setup() {
  tft.begin();
  tft.setRotation(0);
  tft.fillScreen(ILI9341_BLACK);
  tft.drawRect(0, 0, 240, 320, ILI9341_GREEN);
  tft.setTextColor(ILI9341_WHITE);
  tft.setTextSize(2);
  tft.setCursor(18, 30);
  tft.println("CampusID TFT");
  tft.setTextSize(1);
  tft.setCursor(18, 70);
  tft.println("Check all four green edges.");
  tft.fillRect(18, 110, 60, 60, ILI9341_RED);
  tft.fillRect(90, 110, 60, 60, ILI9341_GREEN);
  tft.fillRect(162, 110, 60, 60, ILI9341_BLUE);
  tft.setCursor(18, 285);
  tft.println("240 x 320 portrait");
}

void loop() {}
