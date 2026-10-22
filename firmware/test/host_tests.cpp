#include "pura_core.h"
#include <cmath>
#include <cstdlib>
#include <functional>
#include <iostream>
#include <limits>
#include <stdexcept>
#include <vector>
using namespace pura;
#define CHECK(x) do { if (!(x)) throw std::runtime_error(#x); } while (false)
static int passed = 0;
static void test(const char* name, const std::function<void()>& run) { run(); ++passed; std::cerr << "PASS " << name << '\n'; }
static void put(std::vector<uint8_t>& p, size_t at, uint16_t v) { p[at] = v >> 8; p[at+1] = v & 0xff; }
static std::vector<uint8_t> frame(uint16_t pm25 = 19) {
  std::vector<uint8_t> p(32, 0); p[0] = 0x42; p[1] = 0x4d; put(p, 2, 28);
  put(p, 4, 999); put(p, 6, 999); put(p, 8, 999); // CF=1 values deliberately differ.
  put(p, 10, 11); put(p, 12, pm25); put(p, 14, 45);
  uint16_t sum = 0; for (size_t i=0; i<30; ++i) sum += p[i]; put(p, 30, sum); return p;
}
static bool feed(PmsDecoder& p, const std::vector<uint8_t>& bytes, uint64_t now) { bool ok = false; for (auto b:bytes) ok = p.feed(b, now) || ok; return ok; }
static std::vector<uint8_t> scdWords(uint16_t co2 = 460, uint16_t temp = 25690, uint16_t rh = 31457) {
  std::vector<uint8_t> p(9); put(p, 0, co2); put(p, 3, temp); put(p, 6, rh);
  for (int i=0; i<9; i+=3) p[i+2] = crc8(p.data()+i, 2);
  return p;
}
struct Bus : I2cBus {
  bool nack = false, shortRead = false, ready = true, corrupt = false;
  std::vector<uint16_t> commands;
  bool command(uint16_t w) override { commands.push_back(w); return !nack; }
  bool read(uint8_t* bytes, size_t size) override {
    if (shortRead) return false;
    auto p = scdWords(); if (size == 3) { p.resize(3); put(p,0,ready ? 1 : 0); p[2]=crc8(p.data(),2); }
    if (corrupt) p[2] ^= 1;
    for(size_t i=0;i<size;++i) bytes[i]=p[i];
    return true;
  }
};
struct Wifi : WifiLink { bool online = false; int calls=0; bool connected() override {return online;} void reconnect() override {++calls;} };
struct Http : HttpTransport { int status = 503; std::vector<std::string> payloads; int post(const std::string&, const std::string& json) override {payloads.push_back(json); return status;} };
static Event fixture(uint64_t sequence = 1, uint64_t timestamp = 1792585800000ULL) {
  PmsDecoder decoder; CHECK(feed(decoder,frame(14 + 3 * (sequence-1)),1000));
  ScdReading scd; auto bytes=scdWords(); CHECK(decodeScd(bytes.data(),bytes.size(),1000,scd));
  Clock clock; CHECK(clock.synchronize(timestamp-1000,0)); Event e;
  CHECK(assemble("PA-FW-FIXTURE", "0123456789abcdef0123456789abcdef", sequence, decoder.reading(), scd, 603, true, clock, 1000, e)); return e;
}
int main(int argc, char** argv) {
 try {
  if (argc > 1 && std::string(argv[1]) == "--emit") {
    const uint64_t start=argc>2 ? std::strtoull(argv[2],nullptr,10) : 1792585800000ULL;
    for(uint64_t i=1;i<=3;++i) { std::string json; CHECK(serialize(fixture(i,start+(i-1)*1000),json)); std::cout<<json<<'\n'; } return 0;
  }
  test("PMS atmosphere fields, framing noise and concatenated frames", [] {
    PmsDecoder p; p.feed(0xff,1); p.feed(0x42,1); CHECK(feed(p,frame(),10));
    CHECK(p.reading().pm1==11 && p.reading().pm25==19 && p.reading().pm10==45);
    CHECK(feed(p,frame(20),20)); CHECK(p.reading().pm25==20);
  });
  test("PMS checksum, length, sensor error and out-of-range packets rejected", [] {
    for(int kind=0;kind<4;++kind) { auto bytes=frame();
      if(kind==0) bytes[12]^=1;
      if(kind==1) bytes[3]=27;
      if(kind==2) {bytes[29]=1; uint16_t sum=0; for(int i=0;i<30;++i)sum+=bytes[i];put(bytes,30,sum);}
      if(kind==3) bytes=frame(5001);
      PmsDecoder p; CHECK(!feed(p,bytes,0)); CHECK(!p.reading().valid); CHECK(p.errors()>0);
    }
  });
  test("PMS incomplete packet timeout resynchronizes and old reading ages", [] {
    auto bytes=frame(); PmsDecoder p; for(int i=0;i<12;++i)p.feed(bytes[i],1);
    CHECK(!p.reading().valid); CHECK(feed(p,bytes,502));
    CHECK(!fresh(p.reading().sampled,10503,10000));
  });
  test("PMS7003 reserved word is accepted with valid checksum; corruption is rejected", [] {
    // Synthetic v2.5 packet; not a captured hardware measurement.
    auto bytes = frame(34); bytes[28] = 0x12; bytes[29] = 0x34;
    uint16_t sum = 0; for (size_t i = 0; i < 30; ++i) sum += bytes[i]; put(bytes, 30, sum);
    PmsDecoder p(PmsModel::Pms7003);
    CHECK(feed(p, bytes, 100)); CHECK(p.reading().pm1 == 11 && p.reading().pm25 == 34 && p.reading().pm10 == 45);
    PmsDecoder legacy; CHECK(!feed(legacy, bytes, 100)); // Retain existing mode behavior.
    bytes[12] ^= 1; CHECK(!feed(p, bytes, 200)); CHECK(p.reading().sampled == 100);
  });
  test("PMS7003 rejects wrong lengths and incomplete frames, then resynchronizes", [] {
    PmsDecoder p(PmsModel::Pms7003); auto bytes = frame(); bytes[3] = 27;
    CHECK(!feed(p, bytes, 10)); bytes = frame();
    for (unsigned i = 0; i < 16; ++i) p.feed(bytes[i], 20);
    CHECK(!p.reading().valid); CHECK(feed(p, bytes, 600));
    CHECK(p.reading().pm25 == 19 && p.errors() >= 2);
  });
  test("SCD40 manufacturer CRC vector and physical units", [] {
    uint8_t v[]={0xbe,0xef}; CHECK(crc8(v,2)==0x92);
    auto bytes=scdWords(); ScdReading r; CHECK(decodeScd(bytes.data(),9,50,r));
    CHECK(r.co2==460 && std::abs(r.temperature-23.6009)<0.01 && std::abs(r.humidity-48)<0.01);
  });
  test("SCD40 CRC, short data, zero sentinel and contract range failures", [] {
    auto p=scdWords(); ScdReading r; CHECK(!decodeScd(p.data(),8,0,r)); p[5]^=1; CHECK(!decodeScd(p.data(),9,0,r));
    for(auto p:{scdWords(0),scdWords(50001),scdWords(460,0),scdWords(460,65535)}) CHECK(!decodeScd(p.data(),9,0,r));
    CHECK(!r.valid);
  });
  test("SCD40 stop/start/ready/read sequence and initialization retry", [] {
    Bus bus; Scd40 s; bus.nack=true; s.tick(bus,0); CHECK(s.errors()==1);
    bus.nack=false; s.tick(bus,9999); CHECK(bus.commands.size()==1);
    s.tick(bus,10000); s.tick(bus,10500); s.tick(bus,15500); s.tick(bus,15501); s.tick(bus,15502);
    CHECK(s.reading().valid && s.reading().co2==460); CHECK(bus.commands.back()==0xec05);
  });
  test("SCD40 missing ready times out, malformed response recovers", [] {
    Bus bus; Scd40 s; s.tick(bus,0); s.tick(bus,500); bus.ready=false;
    s.tick(bus,5500); s.tick(bus,5501); s.tick(bus,20501); CHECK(s.errors()==1);
    bus.ready=true; s.tick(bus,30501); s.tick(bus,31001); s.tick(bus,36001); bus.shortRead=true; s.tick(bus,36002); CHECK(s.errors()==2);
    bus.shortRead=false; s.tick(bus,46002); s.tick(bus,46502); s.tick(bus,51502); s.tick(bus,51503); s.tick(bus,51504); CHECK(s.reading().valid);
  });
  test("time unavailable, invalid sync and expired sync never fabricate epoch", [] {
    Clock c; uint64_t t=0; CHECK(!c.at(0,0,t)); CHECK(!c.synchronize(123,0));
    CHECK(c.synchronize(1792585800000ULL,100)); CHECK(c.at(200,300,t) && t==1792585800100ULL);
    CHECK(!c.at(99,300,t)); CHECK(!c.at(200,86400101,t));
  });
  test("stale PM suppresses event, stale SCD is omitted and ADC is raw only", [] {
    Clock c; c.synchronize(1792585800000ULL,0); Event e; PmReading p{11,19,45,1000,true}; ScdReading s{460,23,48,0,true};
    CHECK(!assemble("PA-FW-FIXTURE","boot",1,p,s,0,true,c,11001,e));
    p.sampled=16000; CHECK(assemble("PA-FW-FIXTURE","boot",1,p,s,4095,true,c,16000,e));
    CHECK(!e.scdAvailable && e.mqAvailable && e.mq135Raw==4095);
    CHECK(assemble("PA-FW-FIXTURE","boot",1,p,s,4096,true,c,16000,e) && !e.mqAvailable);
    CHECK(assemble("PA-FW-FIXTURE","boot",1,p,s,0,false,c,16000,e) && !e.mqAvailable);
  });
  test("JSON exact identifiers, optional omission, finite ranges and no gas claims", [] {
    auto e=fixture(); std::string json; CHECK(serialize(e,json)); CHECK(json.find("\"source\":\"hardware\"")!=std::string::npos);
    CHECK(json.find("\"mq135_raw\":603")!=std::string::npos && json.find("gas_index")==std::string::npos);
    e.scdAvailable=false; e.mqAvailable=false; CHECK(serialize(e,json)); CHECK(json.find("co2")==std::string::npos && json.find("mq135_raw")==std::string::npos);
    e.pm25=std::numeric_limits<double>::quiet_NaN(); CHECK(!serialize(e,json) && json.empty());
    e=fixture(); e.deviceId="../bad"; CHECK(!valid(e)); e.deviceId="constructor"; CHECK(!valid(e));
  });
  test("Wi-Fi exponential reconnection is bounded and recovers", [] {
    Wifi w; WifiRecovery r; r.tick(w,0); r.tick(w,999); CHECK(w.calls==1);
    r.tick(w,1000); CHECK(w.calls==2); w.online=true; r.tick(w,1001); w.online=false; r.tick(w,1002); CHECK(w.calls==3);
  });
  test("offline/time failure pause HTTP, retry preserves exact bytes and timestamp", [] {
    Outbox q; Http h; auto e=fixture(); CHECK(q.enqueue(e)); q.tick(h,false,true,0); q.tick(h,true,false,0); CHECK(h.payloads.empty());
    q.tick(h,true,true,0); h.status=-1; q.tick(h,true,true,999); CHECK(h.payloads.size()==1);
    q.tick(h,true,true,1000); h.status=202; q.tick(h,true,true,3000);
    CHECK(q.size()==0 && q.accepted==1 && h.payloads.size()==3); CHECK(h.payloads[0]==h.payloads[1] && h.payloads[1]==h.payloads[2]);
  });
  test("bounded FIFO buffer, overload retries exhaust, no unbounded allocation", [] {
    Outbox q; Http h; for(unsigned i=0;i<4;++i)CHECK(q.enqueue(fixture(i+1)));
    CHECK(!q.enqueue(fixture(5)) && q.dropped==1); for(unsigned i=0;i<8;++i)q.tick(h,true,true,i*60000);
    CHECK(q.exhausted==1 && q.size()==3); h.status=202; q.tick(h,true,true,480000); CHECK(q.accepted==1);
  });
  test("unauthorized latches until corrected reboot; malformed/conflict/redirect terminal", [] {
    Outbox q; Http h; q.enqueue(fixture()); h.status=401; q.tick(h,true,true,0); CHECK(q.unauthorized());
    h.status=202; q.tick(h,true,true,100000); CHECK(h.payloads.size()==1 && q.accepted==0);
    for(int code:{400,409,413,302}) { Outbox other; other.enqueue(fixture()); h.status=code; other.tick(h,true,true,0); CHECK(other.rejected==1 && other.size()==0); }
  });
  test("development host guard and per-boot identity reset policy", [] {
    CHECK(privateIpv4("192.168.1.20") && privateIpv4("172.16.0.1") && privateIpv4("10.0.0.2"));
    CHECK(!privateIpv4("8.8.8.8") && !privateIpv4("127.0.0.1") && !privateIpv4("192.168.1.20.evil"));
    CHECK(!validHost("localhost") && !validHost("https://host/key")); auto a=fixture(), b=fixture(); b.eventId="anotherboot-1"; CHECK(a.eventId!=b.eventId);
  });
  std::cerr<<"HOST_TESTS_PASS count="<<passed<<'\n'; return 0;
 } catch(const std::exception& e) { std::cerr<<"FAIL "<<e.what()<<'\n'; return 1; }
}
