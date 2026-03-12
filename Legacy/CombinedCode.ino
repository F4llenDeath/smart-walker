#include "HX711.h"
#include <Wire.h>
#include <LIDARLite.h>


// ----- HX711 -----
#define calibration_factor -18670.0
#define DOUT  3
#define CLK   2
HX711 scale;


// ----- LIDAR -----
LIDARLite myLidarLite;


// ----- Rate limiting -----
unsigned long lastRead = 0;
const unsigned long interval = 50; // 20 Hz


// ----- Speed calculation state -----
float prev_ft = NAN;
unsigned long prev_ms = 0;
bool ema_initialized = false;
float speed_ema_ft_s = NAN;


// Convert cm → feet
inline float cmToFeet(int cm) { return cm * 0.0328084f; }


// ---------------------------------------------------------------------------
// LIDAR reading + speed calculation
// ---------------------------------------------------------------------------
void updateLidar(float &distance_ft_out, float &speed_ft_s_out)
{
   unsigned long now = millis();
   int dist_cm = myLidarLite.distance(true);


   if (dist_cm <= 0) {
       // Return previous values if invalid reading
       distance_ft_out = prev_ft;
       speed_ft_s_out = speed_ema_ft_s;
       return;
   }


   float dist_ft = cmToFeet(dist_cm);
   float inst_speed_ft_s = NAN;


   if (prev_ms != 0) {
       float dt_s = (now - prev_ms) / 1000.0f;
       if (dt_s > 0) {
           inst_speed_ft_s = (prev_ft - dist_ft) / dt_s; // positive = approaching


           const float alpha = 0.25f; // EMA smoothing
           if (!ema_initialized) {
               speed_ema_ft_s = inst_speed_ft_s;
               ema_initialized = true;
           } else {
               speed_ema_ft_s = alpha * inst_speed_ft_s +
                                (1 - alpha) * speed_ema_ft_s;
           }
       }
   }


   prev_ft = dist_ft;
   prev_ms = now;


   distance_ft_out = dist_ft;
   speed_ft_s_out = (isnan(speed_ema_ft_s) ? 0 : speed_ema_ft_s);
}


// ---------------------------------------------------------------------------
// SETUP
// ---------------------------------------------------------------------------
void setup() {
   Serial.begin(115200);  // Required for Serial Plotter


   Wire.begin();
   delay(200);            // Let LIDAR boot


   // HX711
   scale.begin(DOUT, CLK);
   scale.set_scale(calibration_factor);
   scale.tare();


   // LIDAR
   myLidarLite.begin(0, true);
   myLidarLite.configure(0);
}


// ---------------------------------------------------------------------------
// LOOP — single unified Serial Plotter output line
// ---------------------------------------------------------------------------
void loop() {
   unsigned long now = millis();
   if (now - lastRead >= interval) {
       lastRead = now;


       // ---- Read HX711 ----
       float weight_lbs = scale.get_units(1);


       // ---- Read LIDAR + speed ----
       float dist_ft = 0;
       float speed_ft_s = 0;
       updateLidar(dist_ft, speed_ft_s);


       // ----------------------------------------------------------
       // Unified Serial Plotter Format
       // label:value \t label:value \t label:value
       // ----------------------------------------------------------
       Serial.print("weight_lbs:");
       Serial.print(weight_lbs, 2);
       Serial.print("\t");


       Serial.print("distance_ft:");
       Serial.print(dist_ft, 2);
       Serial.print("\t");


       Serial.print("speed_ft_s:");
       Serial.println(speed_ft_s, 2);
   }
}
