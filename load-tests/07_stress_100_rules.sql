-- pgbench script: Stress test with 100 rules
-- This tests performance with a large number of rules (realistic enterprise scenario)

\set customer_id random(1, 10000)
\set order_total random(100, 10000)
\set order_items random(1, 100)
\set customer_age random(18, 80)
\set customer_years random(0, 20)
\set region_id random(1, 10)

SELECT run_rule_engine(
    format('{"Customer": {"id": %s, "age": %s, "memberYears": %s, "region": %s}, "Order": {"total": %s, "items": %s, "discount": 0, "tax": 0, "shipping": 0, "points": 0}}',
        :customer_id,
        :customer_age,
        :customer_years,
        :region_id,
        :order_total,
        :order_items
    ),
    -- 100 rules covering various business scenarios
    'rule "R001_VIPDiscount" salience 100 {
        when Customer.memberYears >= 10 && Order.total > 1000
        then Order.discount = Order.discount + 100;
    }
    rule "R002_GoldMember" salience 99 {
        when Customer.memberYears >= 5 && Order.total > 500
        then Order.discount = Order.discount + 50;
    }
    rule "R003_SilverMember" salience 98 {
        when Customer.memberYears >= 3 && Order.total > 300
        then Order.discount = Order.discount + 30;
    }
    rule "R004_BronzeMember" salience 97 {
        when Customer.memberYears >= 1 && Order.total > 200
        then Order.discount = Order.discount + 20;
    }
    rule "R005_SeniorDiscount" salience 96 {
        when Customer.age >= 65
        then Order.discount = Order.discount + 25;
    }
    rule "R006_StudentDiscount" salience 95 {
        when Customer.age >= 18 && Customer.age <= 25
        then Order.discount = Order.discount + 15;
    }
    rule "R007_BulkOrder" salience 94 {
        when Order.items >= 50
        then Order.discount = Order.discount + 200;
    }
    rule "R008_MediumBulk" salience 93 {
        when Order.items >= 20 && Order.items < 50
        then Order.discount = Order.discount + 100;
    }
    rule "R009_SmallBulk" salience 92 {
        when Order.items >= 10 && Order.items < 20
        then Order.discount = Order.discount + 50;
    }
    rule "R010_HighValue" salience 91 {
        when Order.total > 5000
        then Order.discount = Order.discount + 500;
    }
    rule "R011_MediumValue" salience 90 {
        when Order.total > 2000 && Order.total <= 5000
        then Order.discount = Order.discount + 200;
    }
    rule "R012_LowValue" salience 89 {
        when Order.total > 1000 && Order.total <= 2000
        then Order.discount = Order.discount + 100;
    }
    rule "R013_Region1Promo" salience 88 {
        when Customer.region == 1
        then Order.discount = Order.discount + 10;
    }
    rule "R014_Region2Promo" salience 87 {
        when Customer.region == 2
        then Order.discount = Order.discount + 20;
    }
    rule "R015_Region3Promo" salience 86 {
        when Customer.region == 3
        then Order.discount = Order.discount + 15;
    }
    rule "R016_FreeShipping1" salience 85 {
        when Order.total > 500
        then Order.shipping = 0;
    }
    rule "R017_FreeShipping2" salience 84 {
        when Order.items >= 10
        then Order.shipping = 0;
    }
    rule "R018_StandardShipping" salience 83 {
        when Order.shipping == 0 && Order.total <= 500
        then Order.shipping = 10;
    }
    rule "R019_LoyaltyPoints1" salience 82 {
        when Order.total > 1000
        then Order.points = Order.total * 0.05;
    }
    rule "R020_LoyaltyPoints2" salience 81 {
        when Order.total > 500 && Order.total <= 1000
        then Order.points = Order.total * 0.03;
    }
    rule "R021_LoyaltyPoints3" salience 80 {
        when Order.total > 100 && Order.total <= 500
        then Order.points = Order.total * 0.01;
    }
    rule "R022_TaxRate1" salience 79 {
        when Customer.region == 1
        then Order.tax = Order.total * 0.10;
    }
    rule "R023_TaxRate2" salience 78 {
        when Customer.region == 2
        then Order.tax = Order.total * 0.08;
    }
    rule "R024_TaxRate3" salience 77 {
        when Customer.region == 3
        then Order.tax = Order.total * 0.06;
    }
    rule "R025_TaxExemptSenior" salience 76 {
        when Customer.age >= 65
        then Order.tax = Order.tax * 0.5;
    }
    rule "R026_FirstTimeBuyer" salience 75 {
        when Customer.memberYears == 0
        then Order.discount = Order.discount + 50;
    }
    rule "R027_WeekendBonus" salience 74 {
        when Order.total > 300
        then Order.discount = Order.discount + 10;
    }
    rule "R028_FlashSale" salience 73 {
        when Order.items >= 5
        then Order.discount = Order.discount + 25;
    }
    rule "R029_ClearanceSale" salience 72 {
        when Order.total > 200
        then Order.discount = Order.discount + 15;
    }
    rule "R030_SeasonalPromo" salience 71 {
        when Customer.memberYears >= 2
        then Order.discount = Order.discount + 20;
    }
    rule "R031_BirthdayMonth" salience 70 {
        when Customer.age > 0
        then Order.points = Order.points + 100;
    }
    rule "R032_ReferralBonus" salience 69 {
        when Customer.memberYears >= 1
        then Order.points = Order.points + 50;
    }
    rule "R033_SocialMediaShare" salience 68 {
        when Order.total > 100
        then Order.discount = Order.discount + 5;
    }
    rule "R034_NewsletterSub" salience 67 {
        when Customer.memberYears >= 0
        then Order.points = Order.points + 25;
    }
    rule "R035_AppDownload" salience 66 {
        when Order.total > 50
        then Order.discount = Order.discount + 10;
    }
    rule "R036_ReviewBonus" salience 65 {
        when Customer.memberYears >= 1
        then Order.points = Order.points + 75;
    }
    rule "R037_PhotoUpload" salience 64 {
        when Order.items >= 3
        then Order.points = Order.points + 30;
    }
    rule "R038_VideoReview" salience 63 {
        when Customer.memberYears >= 2
        then Order.points = Order.points + 150;
    }
    rule "R039_EarlyBird" salience 62 {
        when Order.total > 400
        then Order.discount = Order.discount + 40;
    }
    rule "R040_NightOwl" salience 61 {
        when Order.total > 350
        then Order.discount = Order.discount + 35;
    }
    rule "R041_BundleDeal1" salience 60 {
        when Order.items >= 15
        then Order.discount = Order.discount + 60;
    }
    rule "R042_BundleDeal2" salience 59 {
        when Order.items >= 8 && Order.items < 15
        then Order.discount = Order.discount + 30;
    }
    rule "R043_ComboOffer" salience 58 {
        when Order.items >= 4 && Order.total > 150
        then Order.discount = Order.discount + 20;
    }
    rule "R044_PremiumPackage" salience 57 {
        when Order.total > 3000
        then Order.shipping = 0;
    }
    rule "R045_GiftWrapping" salience 56 {
        when Order.items <= 3
        then Order.points = Order.points + 10;
    }
    rule "R046_ExpressDelivery" salience 55 {
        when Order.total > 800
        then Order.shipping = Order.shipping + 15;
    }
    rule "R047_InsuranceOffer" salience 54 {
        when Order.total > 1500
        then Order.points = Order.points + 200;
    }
    rule "R048_ExtendedWarranty" salience 53 {
        when Order.total > 2000
        then Order.discount = Order.discount + 100;
    }
    rule "R049_PriceMatch" salience 52 {
        when Order.total > 600
        then Order.discount = Order.discount + 30;
    }
    rule "R050_ReturnPolicy" salience 51 {
        when Customer.memberYears >= 3
        then Order.points = Order.points + 40;
    }
    rule "R051_LoyalCustomer" salience 50 {
        when Customer.memberYears >= 8
        then Order.discount = Order.discount + 80;
    }
    rule "R052_PlatinumTier" salience 49 {
        when Customer.memberYears >= 15
        then Order.discount = Order.discount + 150;
    }
    rule "R053_DiamondTier" salience 48 {
        when Customer.memberYears >= 20
        then Order.discount = Order.discount + 250;
    }
    rule "R054_MilestoneReward" salience 47 {
        when Customer.memberYears == 5
        then Order.points = Order.points + 500;
    }
    rule "R055_AnniversaryBonus" salience 46 {
        when Customer.memberYears == 10
        then Order.points = Order.points + 1000;
    }
    rule "R056_LifetimeValue" salience 45 {
        when Customer.memberYears >= 12
        then Order.discount = Order.discount + 120;
    }
    rule "R057_ChampionCustomer" salience 44 {
        when Customer.memberYears >= 18
        then Order.discount = Order.discount + 200;
    }
    rule "R058_EliteStatus" salience 43 {
        when Customer.memberYears >= 7 && Order.total > 1200
        then Order.discount = Order.discount + 100;
    }
    rule "R059_VIPLounge" salience 42 {
        when Customer.memberYears >= 6
        then Order.points = Order.points + 300;
    }
    rule "R060_PersonalShopper" salience 41 {
        when Order.total > 4000
        then Order.discount = Order.discount + 400;
    }
    rule "R061_ConciergeService" salience 40 {
        when Customer.memberYears >= 9
        then Order.points = Order.points + 450;
    }
    rule "R062_PrioritySupport" salience 39 {
        when Customer.memberYears >= 4
        then Order.discount = Order.discount + 40;
    }
    rule "R063_FastTrack" salience 38 {
        when Order.total > 1800
        then Order.shipping = Order.shipping - 5;
    }
    rule "R064_WhiteGlove" salience 37 {
        when Order.total > 3500
        then Order.points = Order.points + 700;
    }
    rule "R065_VirtualAssistant" salience 36 {
        when Customer.memberYears >= 5
        then Order.discount = Order.discount + 50;
    }
    rule "R066_SmartRecommendations" salience 35 {
        when Order.items >= 6
        then Order.points = Order.points + 60;
    }
    rule "R067_TrendingProducts" salience 34 {
        when Order.total > 700
        then Order.discount = Order.discount + 35;
    }
    rule "R068_NewArrivals" salience 33 {
        when Order.items >= 12
        then Order.discount = Order.discount + 70;
    }
    rule "R069_BestSellers" salience 32 {
        when Order.total > 900
        then Order.points = Order.points + 90;
    }
    rule "R070_LimitedEdition" salience 31 {
        when Order.total > 2500
        then Order.discount = Order.discount + 150;
    }
    rule "R071_ExclusiveAccess" salience 30 {
        when Customer.memberYears >= 11
        then Order.points = Order.points + 550;
    }
    rule "R072_PreOrder" salience 29 {
        when Order.total > 1100
        then Order.discount = Order.discount + 55;
    }
    rule "R073_BackInStock" salience 28 {
        when Order.items >= 7
        then Order.points = Order.points + 35;
    }
    rule "R074_WaitList" salience 27 {
        when Customer.memberYears >= 4
        then Order.discount = Order.discount + 45;
    }
    rule "R075_ComingSoon" salience 26 {
        when Order.total > 1300
        then Order.points = Order.points + 130;
    }
    rule "R076_FlashDeal" salience 25 {
        when Order.items >= 9
        then Order.discount = Order.discount + 45;
    }
    rule "R077_DailyDeal" salience 24 {
        when Order.total > 550
        then Order.discount = Order.discount + 27;
    }
    rule "R078_WeeklySpecial" salience 23 {
        when Order.items >= 11
        then Order.points = Order.points + 55;
    }
    rule "R079_MonthlyPromo" salience 22 {
        when Customer.memberYears >= 2
        then Order.discount = Order.discount + 22;
    }
    rule "R080_QuarterlyBonus" salience 21 {
        when Order.total > 1600
        then Order.points = Order.points + 320;
    }
    rule "R081_AnnualSale" salience 20 {
        when Order.items >= 13
        then Order.discount = Order.discount + 85;
    }
    rule "R082_BlackFriday" salience 19 {
        when Order.total > 1900
        then Order.discount = Order.discount + 190;
    }
    rule "R083_CyberMonday" salience 18 {
        when Order.items >= 16
        then Order.discount = Order.discount + 95;
    }
    rule "R084_ChristmasSale" salience 17 {
        when Order.total > 2200
        then Order.points = Order.points + 440;
    }
    rule "R085_NewYearPromo" salience 16 {
        when Customer.memberYears >= 6
        then Order.discount = Order.discount + 60;
    }
    rule "R086_ValentineSpecial" salience 15 {
        when Order.total > 750
        then Order.discount = Order.discount + 37;
    }
    rule "R087_SpringSale" salience 14 {
        when Order.items >= 14
        then Order.points = Order.points + 70;
    }
    rule "R088_SummerDeal" salience 13 {
        when Order.total > 1400
        then Order.discount = Order.discount + 70;
    }
    rule "R089_FallPromo" salience 12 {
        when Customer.memberYears >= 7
        then Order.points = Order.points + 350;
    }
    rule "R090_WinterSpecial" salience 11 {
        when Order.total > 1700
        then Order.discount = Order.discount + 85;
    }
    rule "R091_BackToSchool" salience 10 {
        when Order.items >= 17
        then Order.discount = Order.discount + 100;
    }
    rule "R092_CollegeStudent" salience 9 {
        when Customer.age >= 18 && Customer.age <= 23
        then Order.discount = Order.discount + 18;
    }
    rule "R093_Military" salience 8 {
        when Customer.memberYears >= 1
        then Order.discount = Order.discount + 50;
    }
    rule "R094_FirstResponder" salience 7 {
        when Customer.age >= 21
        then Order.discount = Order.discount + 40;
    }
    rule "R095_Healthcare" salience 6 {
        when Order.total > 800
        then Order.discount = Order.discount + 40;
    }
    rule "R096_Teacher" salience 5 {
        when Customer.memberYears >= 2
        then Order.discount = Order.discount + 30;
    }
    rule "R097_Corporate" salience 4 {
        when Order.items >= 25
        then Order.discount = Order.discount + 125;
    }
    rule "R098_Government" salience 3 {
        when Order.total > 2800
        then Order.discount = Order.discount + 140;
    }
    rule "R099_NonProfit" salience 2 {
        when Customer.memberYears >= 3
        then Order.discount = Order.discount + 60;
    }
    rule "R100_FinalBonus" salience 1 {
        when Order.total > 100
        then Order.points = Order.points + 10;
    }'
)::jsonb;
