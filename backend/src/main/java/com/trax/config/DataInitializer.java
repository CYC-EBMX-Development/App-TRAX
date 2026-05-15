package com.trax.config;

import com.trax.model.*;
import com.trax.repository.*;
import com.trax.service.ImageDownloadService;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.Map;

@Component
public class DataInitializer implements ApplicationRunner {

    private final BikeBrandRepository brandRepo;
    private final BikeModelRepository modelRepo;
    private final TraxModuleRepository moduleRepo;
    private final UserRepository userRepo;
    private final ImageDownloadService imageDownloadService;

    @Value("${app.public-base-url:http://localhost:8080}")
    private String publicBaseUrl;

    public DataInitializer(BikeBrandRepository brandRepo,
                           BikeModelRepository modelRepo,
                           TraxModuleRepository moduleRepo,
                           UserRepository userRepo,
                           ImageDownloadService imageDownloadService) {
        this.brandRepo = brandRepo;
        this.modelRepo = modelRepo;
        this.moduleRepo = moduleRepo;
        this.userRepo = userRepo;
        this.imageDownloadService = imageDownloadService;
    }

    @Override
    @Transactional
    public void run(ApplicationArguments args) {
        // Only seed if database is empty (i.e., first startup)
        if (brandRepo.count() == 0) {
            seedBaseData();
        }
        // Always run patches (safe to re-run, only adds missing entries)
        patchModules();
        patchUserAvatars();
    }

    /** Full base seeding — runs only once when the DB is empty. */
    private void seedBaseData() {
        if (brandRepo.count() > 0) return;

        // ─── Brands ───────────────────────────────────────────────
        BikeBrand bonnell    = brand("BONNELL");
        BikeBrand ristretto  = brand("RISTRETTO");
        BikeBrand talaria    = brand("Talaria");
        BikeBrand surRon     = brand("Sur-Ron");
        BikeBrand eRide      = brand("E Ride");
        BikeBrand rerode     = brand("RERODE");

        // ─── BONNELL models ──────────────────────────────────────
        BikeModel b775mx = model(bonnell, "775 MX",  "CYC X1 Pro Gen4", 6000,  280, "CYC A65",        "65V",   1300, "CYC Controller V4");
        BikeModel b775am = model(bonnell, "775 AM",  "CYC Photon",      1200,  110, "CYC A-Series",   "52V",    520, "CYC Photon Controller");
        BikeModel b805   = model(bonnell, "805",     "805 Motor",       3000,  110, "805 24s Core",   null,   3100, "EBMX X9000-V3");
        BikeModel b902   = model(bonnell, "902",     "902 Motor",       4600,  110, "902 24s Sprint", null,   6600, "EBMX X48");

        // ─── RISTRETTO models ─────────────────────────────────────
        /*BikeModel r512a20 =*/ model(ristretto, "512 A20", "RISTRETTO 512 A20 Motor", 4500, null, "Catalina Battery Pack", "52V", 1550, "Catalina Controller");
        /*BikeModel r512a24 =*/ model(ristretto, "512 A24", "RISTRETTO 512 A24 Motor", 4500, null, "Catalina Battery Pack", "52V", 1550, "Catalina Controller");

        // ─── Talaria models ───────────────────────────────────────
        /*BikeModel tx3pro   =*/ model(talaria, "X3 Pro",             "Talaria X3 Pro",   5500, null, "Talaria Stock XXX",  "60V", 2400, "Talaria X3 Controller");
        /*BikeModel tkomodo  =*/ model(talaria, "Komodo",             "Talaria Komodo",   3200,   90, "Talaria Komodo",    "96V", 4300, "Talaria Komodo Controller");
        /*BikeModel tmx5     =*/ model(talaria, "Sting MX5",          "Talaria MX5",     13400,   90, "Talaria MX5",       "72V", 2880, "Talaria MX5 Controller");
        /*BikeModel tle1     =*/ model(talaria, "Sting LE1/MX",       "Talaria Sting",    6000,   34, "Talaria Sting",     "60V", 2300, "Talaria Sting Controller");
        /*BikeModel tdragon  =*/ model(talaria, "Dragon",             "Talaria Dragon",  28000,  630, "Talaria Dragon",    null,  5200, "Talaria Dragon Controller");
        /*BikeModel tmx4r    =*/ model(talaria, "Sting R MX4 Expert", "Talaria Sting R",  6000,   34, "Talaria Sting MX4", "60V", 2280, "Talaria Sting R Controller");
        /*BikeModel tmx4     =*/ model(talaria, "Sting MX4",          "Talaria Sting MX4", null, null, "Talaria Sting MX4","60V", 2700, null);
        /*BikeModel tmx3     =*/ model(talaria, "Sting MX3",          "Talaria Sting MX4", null, null, "Talaria Sting MX4","60V", 2700, null);
        /*BikeModel txxx     =*/ model(talaria, "X3 (XXX)",           "Talaria XXX",      6500, null, "Talaria XXX",       "60V", 2400, "Talaria XXX Controller");

        // ─── Sur-Ron models ───────────────────────────────────────
        /*BikeModel shb1412 =*/ model(surRon, "Hyper Bee 14/12", null,  5000, 159, null, "50.4V", 1260, null);
        /*BikeModel shb1210 =*/ model(surRon, "Hyper Bee 12/10", null,  5000, 143, null, "50.4V", 1260, null);
        BikeModel slbx     =    model(surRon, "Light Bee X",     null,  8000, 266, null, "60V",   2400, "KO RUSH (F-SPEC)");
        /*BikeModel slbl    =*/ model(surRon, "Light Bee L",     null,  8000, 266, null, "60V",   2400, "KO RUSH (L-SPEC)");
        /*BikeModel subhp   =*/ model(surRon, "Ultra Bee HP",    null, 21000, 511, null, "74V",   4440, "KO HP");
        BikeModel subr     =    model(surRon, "Ultra Bee R",     null, 12500, 440, null, "74V",   4070, "KO PRO");
        /*BikeModel subt    =*/ model(surRon, "Ultra Bee T",     null, 12500, 440, null, "74V",   4070, "KO PRO");
        /*BikeModel ssbe    =*/ model(surRon, "Storm Bee E",     null, 22500, 440, null, "104V",  5720, "KO Storm");
        /*BikeModel ssbf    =*/ model(surRon, "Storm Bee F",     null, 22500, 520, null, "104V",  5720, "KO Storm");

        // ─── E Ride models ────────────────────────────────────────
        /*BikeModel epsr  =*/ model(eRide, "Pro-SR",    null, 25000, null, null, "72V", 3600, null);
        /*BikeModel eps   =*/ model(eRide, "Pro-S",     null,  8000, null, null, "72V", 2160, null);
        /*BikeModel epss2 =*/ model(eRide, "Pro-SS 2.0",null, 12000, null, null, "72V", 2880, null);
        /*BikeModel epss3 =*/ model(eRide, "Pro-SS 3.0",null, 15800, null, null, "72V", 3600, null);
        /*BikeModel emini =*/ model(eRide, "Mini",      null,  6000,  210, null, "60V", 1800, null);

        // ─── RERODE models ────────────────────────────────────────
        /*BikeModel rr1  =*/ model(rerode, "R1",  null,  8000, 330, null, "72V", 2520, null);
        /*BikeModel rr1p =*/ model(rerode, "R1+", null, 10000, 390, null, "72V", 2520, null);

        // ─── Download or create images for all models ──────────────────
        downloadImagesForAllModels();

        // ─── 直接关联 modules 到 models（不再使用 bike_spec）──────────────────
        module("TRX-7A2B", "CYC TRAX Module",     false, b775mx);   // CYC Gen4
        module("TRX-3F9C", "Sur-Ron Custom Build", true,  slbx);    // Sur-Ron Light Bee X
        module("TRX-12DE", "Generic TRAX Module",  false, null);    // no model
        module("TRX-4B1A", "CYC TRAX Module",      false, b775am);  // CYC Photon
        module("TRX-9D5B", "BONNELL 805 Module",   false, b805);    // BONNELL 805
        module("TRX-8C3A", "BONNELL 902 Module",   false, b902);    // BONNELL 902
    }

    /** Additive patches — runs every startup, safe to re-run. Add new entries here instead of modifying seedBaseData(). */
    private void patchModules() {
        // 补充 TRX-9D5B（如果之前缺失） ─ BONNELL 805 / EBMX X9000-V3
        if (moduleRepo.findBySerialNo("TRX-9D5B").isEmpty()) {
            BikeModel b805 = modelRepo.findByModelNameAndBrand_Name("805", "BONNELL").orElse(null);
            if (b805 != null) {
                module("TRX-9D5B", "BONNELL 805 Module", false, b805);
            }
        }
        // 补充 TRX-8C3A（如果之前缺失） ─ BONNELL 902 / EBMX X48
        if (moduleRepo.findBySerialNo("TRX-8C3A").isEmpty()) {
            BikeModel b902 = modelRepo.findByModelNameAndBrand_Name("902", "BONNELL").orElse(null);
            if (b902 != null) {
                module("TRX-8C3A", "BONNELL 902 Module", false, b902);
            }
        }
    }

    /**
     * Seed well-known accounts' avatars to local images served from /images/avatars/.
     * Only fills the URL when the user has no avatar yet — never clobbers a user-uploaded one.
     */
    private void patchUserAvatars() {
        String base = publicBaseUrl != null && !publicBaseUrl.isEmpty()
                ? publicBaseUrl.replaceAll("/+$", "")
                : "http://localhost:8080";
        Map<String, String> nameToAvatar = Map.of(
                "Joshua", base + "/images/avatars/joshua.png",
                "Steve",  base + "/images/avatars/steve.png",
                "Royce",  base + "/images/avatars/royce.png"
        );
        for (User u : userRepo.findAll()) {
            String n = u.getName();
            if (n == null) continue;
            String url = nameToAvatar.get(n);
            if (url == null) continue;
            String existing = u.getAvatarUrl();
            // Only seed when missing; do NOT overwrite an existing (possibly user-uploaded) URL.
            // Also migrate the legacy hardcoded localhost:8080 form once.
            boolean isLegacyLocalhost = existing != null
                    && existing.startsWith("http://localhost:8080/images/avatars/");
            if (existing == null || existing.isEmpty() || isLegacyLocalhost) {
                u.setAvatarUrl(url);
                userRepo.save(u);
            }
        }
    }

    // ─── Helpers ──────────────────────────────────────────────────

    private BikeBrand brand(String name) {
        BikeBrand b = new BikeBrand();
        b.setName(name);
        return brandRepo.save(b);
    }

    private BikeModel model(BikeBrand brand, String modelName, String motorType,
                            Integer peakPower, Integer torque,
                            String batteryType, String voltage, Integer capacityWh, String controller) {
        BikeModel m = new BikeModel();
        m.setBrand(brand);
        m.setModelName(modelName);
        m.setMotorType(motorType);
        m.setMotorPeakPowerW(peakPower);
        m.setMotorTorqueNm(torque);
        m.setBatteryType(batteryType);
        m.setBatteryVoltage(voltage);
        m.setBatteryCapacityWh(capacityWh);
        m.setController(controller);
        return modelRepo.save(m);
    }

    private void module(String serialNo, String name, boolean bound, BikeModel model) {
        TraxModule m = new TraxModule();
        m.setSerialNo(serialNo);
        m.setName(name);
        m.setBound(bound);
        m.setModel(model);
        moduleRepo.save(m);
    }

    private void downloadImagesForAllModels() {
        List<BikeModel> allModels = modelRepo.findAll();
        for (BikeModel model : allModels) {
            String brand = model.getBrand() != null ? model.getBrand().getName() : "Unknown";
            String modelName = model.getModelName();

            // Try to download image, fallback to placeholder
            String imageUrl = imageDownloadService.downloadBikeImage(brand, modelName);
            if (imageUrl == null) {
                // Create placeholder image if download fails
                imageUrl = imageDownloadService.createPlaceholderImage(brand, modelName);
            }

            // Set the image URL
            if (imageUrl != null) {
                model.setImageUrl(imageUrl);
                modelRepo.save(model);
            }
        }
    }
}
