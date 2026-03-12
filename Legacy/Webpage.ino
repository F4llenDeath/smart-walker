#include <Wire.h>
#include <LIDARLite.h>
#include <WiFiS3.h>


// Load Cell
#define calibration_factor -18670.0
#define DOUT 3
#define CLK 2
HX711 scale;


// LIDAR
LIDARLite myLidarLite;


// WiFi Access Point
const char* ssid = "Smart_Walker";
const char* password = "12345678";
WiFiServer server(80);


// Update timing
unsigned long lastRead = 0;
const unsigned long sensorInterval = 50;   // 20 Hz
const unsigned long webpageInterval = 1000; // 1s refresh


// Speed State
float prev_ft = NAN;
unsigned long prev_ms = 0;
float speed_ema_ft_s = NAN;
bool ema_initialized = false;


// Latest values
float distance_ft = 0;
float speed_ft_s = 0;
float weight_lbs = 0;


// Trial Control
bool trialRunning = false;
float trialWeightSum = 0;
unsigned long trialWeightCount = 0;


// NEW: Trial metrics
float trialStartDist = NAN;
float trialEndDist = NAN;


// NEW: Avg speed during trial
float trialSpeedSum = 0;
unsigned long trialSpeedCount = 0;


// Convert LIDAR cm → feet
inline float cmToFeet(int cm) { return cm * 0.0328084f; }


// Calculate LIDAR distance + smoothed speed
void updateLidar(float &dist_out, float &speed_out) {
   unsigned long now = millis();
   int d = myLidarLite.distance(true);
   if (d <= 0) return;


   float dist_ft = cmToFeet(d);
   float instant = 0;


   if (prev_ms) {
       float dt = (now - prev_ms) / 1000.0;
       if (dt > 0) {
           // NOTE: speed = previous − current (walking toward sensor positive)
           instant = (prev_ft - dist_ft) / dt;


           const float alpha = 0.25;
           if (!ema_initialized) {
               speed_ema_ft_s = instant;
               ema_initialized = true;
           }
           else {
               speed_ema_ft_s = alpha * instant + (1 - alpha) * speed_ema_ft_s;
           }
       }
   }
   prev_ft = dist_ft;
   prev_ms = now;


   dist_out = dist_ft;
   speed_out = speed_ema_ft_s;
}


// Return HTML for 1s auto refresh
void sendWeb(WiFiClient &client) {
   client.println("HTTP/1.1 200 OK");
   client.println("Content-Type: text/html");
   client.println("Connection: close");
   client.println();
   client.println("<!DOCTYPE html><html><head>");
   client.println("<meta charset='UTF-8'>");
   client.println("<meta name='viewport' content='width=device-width'>");
   client.println("<meta http-equiv='refresh' content='1'>");
   client.println("<style>");
   client.println("body{font-family:Arial;text-align:center;}");
   client.println("h1{margin-top:18px;}");
   client.println("div{font-size:1.5em;margin:10px;}");
   client.println(".btn{padding:10px 20px;margin:5px;font-size:1em;border:none;border-radius:6px;}");
   client.println(".start{background:#4CAF50;color:white;}");
   client.println(".stop{background:#d32f2f;color:white;}");
   client.println("</style>");
   client.println("</head><body>");
   client.println("<h1>Smart Walker Live Telemetry</h1>");
   client.print("<div>Status: ");
   client.print(trialRunning ? "RUNNING" : "STOPPED");
   client.println("</div>");
   client.print("<div>Weight (lbs): "); client.print(weight_lbs, 2); client.println("</div>");
   client.print("<div>Distance (ft): "); client.print(distance_ft, 2); client.println("</div>");
   client.print("<div>Speed (ft/s): "); client.print(speed_ft_s, 2); client.println("</div>");
   client.println("<a href='/start'><button class='btn start'>Start Trial</button></a>");
   client.println("<a href='/stop'><button class='btn stop'>Stop Trial</button></a>");
   client.println("<p>Page auto-refreshes every 1 second.</p>");
   client.println("</body></html>");
}


// SETUP
void setup() {
   Serial.begin(115200);


   // Sensors
   Wire.begin();
   delay(200);
   scale.begin(DOUT, CLK);
   scale.set_scale(calibration_factor);
   scale.tare();


   myLidarLite.begin(0, true);
   myLidarLite.configure(0);


   // WiFi
   WiFi.beginAP(ssid, password);
   delay(500);
   Serial.print("WiFi AP IP: ");
   Serial.println(WiFi.localIP());
   server.begin();
}


// LOOP
void loop() {
   unsigned long now = millis();


   // SENSOR LOOP (20 Hz)
   if (trialRunning && now - lastRead >= sensorInterval) {
       lastRead = now;


       // Weight
       weight_lbs = scale.get_units(10);


       // Distance + speed
       updateLidar(distance_ft, speed_ft_s);


       // Track average weight
       trialWeightSum += weight_lbs;
       trialWeightCount++;


       // NEW — track speed average
       if (!isnan(speed_ft_s)) {
           trialSpeedSum += speed_ft_s;
           trialSpeedCount++;
       }


       // NEW — track end distance always
       trialEndDist = distance_ft;


       Serial.print("weight:"); Serial.print(weight_lbs,2);
       Serial.print("\tdist:"); Serial.print(distance_ft,2);
       Serial.print("\tspeed:"); Serial.println(speed_ft_s,2);
   }


   // WEB REQUEST HANDLING
   WiFiClient client = server.available();
   if (client) {
       while (client.connected() && !client.available()) delay(1);
       String req = client.readStringUntil('\r');
       client.flush();


       // Handle start/stop trial
       if (req.indexOf("GET /start") >= 0) {
           trialRunning = true;


           // reset metrics
           trialWeightSum = 0;
           trialWeightCount = 0;


           trialSpeedSum = 0;
           trialSpeedCount = 0;


           trialStartDist = distance_ft;
           trialEndDist   = distance_ft;


           Serial.println("=== Trial START ===");
       }


       if (req.indexOf("GET /stop") >= 0) {
           trialRunning = false;
           Serial.println("=== Trial STOP ===");


           // ---- AVERAGE WEIGHT
           if (trialWeightCount > 0) {
               float avgWeight = trialWeightSum / trialWeightCount;
               Serial.print("Trial Average Weight (lbs): ");
               Serial.println(avgWeight, 2);
           }


           // ---- NEW: AVERAGE SPEED
           if (trialSpeedCount > 0) {
               float avgSpeed = trialSpeedSum / trialSpeedCount;
               Serial.print("Trial Average Speed (ft/s): ");
               Serial.println(avgSpeed, 2);
           }


           // ---- NEW: ABSOLUTE ΔDISTANCE
           if (!isnan(trialStartDist) && !isnan(trialEndDist)) {
               float deltaAbs = fabs(trialEndDist - trialStartDist);
               Serial.print("Absolute ΔDistance (ft): ");
               Serial.println(deltaAbs, 2);
           }
       }


       sendWeb(client);
       client.stop();
   }
}
