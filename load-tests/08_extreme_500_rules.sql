-- pgbench script: Extreme stress test with 500 rules
-- This validates scaling beyond typical enterprise scenarios

\set customer_id random(1, 10000)
\set order_total random(100, 10000)
\set order_items random(1, 100)
\set customer_age random(18, 80)
\set customer_years random(0, 20)
\set region_id random(1, 10)

SELECT run_rule_engine(
    format('{"Customer": {"id": %s, "age": %s, "memberYears": %s, "region": %s}, "Order": {"total": %s, "items": %s, "discount": 0}}',
        :customer_id, :customer_age, :customer_years, :region_id, :order_total, :order_items
    ),
    '
    rule "R1" salience 500 {
        when Order.total > 60
        then Order.discount = Order.discount + 2;
    }
    rule "R2" salience 499 {
        when Order.total > 70
        then Order.discount = Order.discount + 3;
    }
    rule "R3" salience 498 {
        when Order.total > 80
        then Order.discount = Order.discount + 4;
    }
    rule "R4" salience 497 {
        when Order.total > 90
        then Order.discount = Order.discount + 5;
    }
    rule "R5" salience 496 {
        when Order.total > 100
        then Order.discount = Order.discount + 6;
    }
    rule "R6" salience 495 {
        when Order.total > 110
        then Order.discount = Order.discount + 7;
    }
    rule "R7" salience 494 {
        when Order.total > 120
        then Order.discount = Order.discount + 8;
    }
    rule "R8" salience 493 {
        when Order.total > 130
        then Order.discount = Order.discount + 9;
    }
    rule "R9" salience 492 {
        when Order.total > 140
        then Order.discount = Order.discount + 10;
    }
    rule "R10" salience 491 {
        when Order.total > 150
        then Order.discount = Order.discount + 11;
    }
    rule "R11" salience 490 {
        when Order.total > 160
        then Order.discount = Order.discount + 12;
    }
    rule "R12" salience 489 {
        when Order.total > 170
        then Order.discount = Order.discount + 13;
    }
    rule "R13" salience 488 {
        when Order.total > 180
        then Order.discount = Order.discount + 14;
    }
    rule "R14" salience 487 {
        when Order.total > 190
        then Order.discount = Order.discount + 15;
    }
    rule "R15" salience 486 {
        when Order.total > 200
        then Order.discount = Order.discount + 16;
    }
    rule "R16" salience 485 {
        when Order.total > 210
        then Order.discount = Order.discount + 17;
    }
    rule "R17" salience 484 {
        when Order.total > 220
        then Order.discount = Order.discount + 18;
    }
    rule "R18" salience 483 {
        when Order.total > 230
        then Order.discount = Order.discount + 19;
    }
    rule "R19" salience 482 {
        when Order.total > 240
        then Order.discount = Order.discount + 20;
    }
    rule "R20" salience 481 {
        when Order.total > 250
        then Order.discount = Order.discount + 21;
    }
    rule "R21" salience 480 {
        when Order.total > 260
        then Order.discount = Order.discount + 22;
    }
    rule "R22" salience 479 {
        when Order.total > 270
        then Order.discount = Order.discount + 23;
    }
    rule "R23" salience 478 {
        when Order.total > 280
        then Order.discount = Order.discount + 24;
    }
    rule "R24" salience 477 {
        when Order.total > 290
        then Order.discount = Order.discount + 25;
    }
    rule "R25" salience 476 {
        when Order.total > 300
        then Order.discount = Order.discount + 26;
    }
    rule "R26" salience 475 {
        when Order.total > 310
        then Order.discount = Order.discount + 27;
    }
    rule "R27" salience 474 {
        when Order.total > 320
        then Order.discount = Order.discount + 28;
    }
    rule "R28" salience 473 {
        when Order.total > 330
        then Order.discount = Order.discount + 29;
    }
    rule "R29" salience 472 {
        when Order.total > 340
        then Order.discount = Order.discount + 30;
    }
    rule "R30" salience 471 {
        when Order.total > 350
        then Order.discount = Order.discount + 31;
    }
    rule "R31" salience 470 {
        when Order.total > 360
        then Order.discount = Order.discount + 32;
    }
    rule "R32" salience 469 {
        when Order.total > 370
        then Order.discount = Order.discount + 33;
    }
    rule "R33" salience 468 {
        when Order.total > 380
        then Order.discount = Order.discount + 34;
    }
    rule "R34" salience 467 {
        when Order.total > 390
        then Order.discount = Order.discount + 35;
    }
    rule "R35" salience 466 {
        when Order.total > 400
        then Order.discount = Order.discount + 36;
    }
    rule "R36" salience 465 {
        when Order.total > 410
        then Order.discount = Order.discount + 37;
    }
    rule "R37" salience 464 {
        when Order.total > 420
        then Order.discount = Order.discount + 38;
    }
    rule "R38" salience 463 {
        when Order.total > 430
        then Order.discount = Order.discount + 39;
    }
    rule "R39" salience 462 {
        when Order.total > 440
        then Order.discount = Order.discount + 40;
    }
    rule "R40" salience 461 {
        when Order.total > 450
        then Order.discount = Order.discount + 41;
    }
    rule "R41" salience 460 {
        when Order.total > 460
        then Order.discount = Order.discount + 42;
    }
    rule "R42" salience 459 {
        when Order.total > 470
        then Order.discount = Order.discount + 43;
    }
    rule "R43" salience 458 {
        when Order.total > 480
        then Order.discount = Order.discount + 44;
    }
    rule "R44" salience 457 {
        when Order.total > 490
        then Order.discount = Order.discount + 45;
    }
    rule "R45" salience 456 {
        when Order.total > 500
        then Order.discount = Order.discount + 46;
    }
    rule "R46" salience 455 {
        when Order.total > 510
        then Order.discount = Order.discount + 47;
    }
    rule "R47" salience 454 {
        when Order.total > 520
        then Order.discount = Order.discount + 48;
    }
    rule "R48" salience 453 {
        when Order.total > 530
        then Order.discount = Order.discount + 49;
    }
    rule "R49" salience 452 {
        when Order.total > 540
        then Order.discount = Order.discount + 50;
    }
    rule "R50" salience 451 {
        when Order.total > 550
        then Order.discount = Order.discount + 1;
    }
    rule "R51" salience 450 {
        when Order.total > 560
        then Order.discount = Order.discount + 2;
    }
    rule "R52" salience 449 {
        when Order.total > 570
        then Order.discount = Order.discount + 3;
    }
    rule "R53" salience 448 {
        when Order.total > 580
        then Order.discount = Order.discount + 4;
    }
    rule "R54" salience 447 {
        when Order.total > 590
        then Order.discount = Order.discount + 5;
    }
    rule "R55" salience 446 {
        when Order.total > 600
        then Order.discount = Order.discount + 6;
    }
    rule "R56" salience 445 {
        when Order.total > 610
        then Order.discount = Order.discount + 7;
    }
    rule "R57" salience 444 {
        when Order.total > 620
        then Order.discount = Order.discount + 8;
    }
    rule "R58" salience 443 {
        when Order.total > 630
        then Order.discount = Order.discount + 9;
    }
    rule "R59" salience 442 {
        when Order.total > 640
        then Order.discount = Order.discount + 10;
    }
    rule "R60" salience 441 {
        when Order.total > 650
        then Order.discount = Order.discount + 11;
    }
    rule "R61" salience 440 {
        when Order.total > 660
        then Order.discount = Order.discount + 12;
    }
    rule "R62" salience 439 {
        when Order.total > 670
        then Order.discount = Order.discount + 13;
    }
    rule "R63" salience 438 {
        when Order.total > 680
        then Order.discount = Order.discount + 14;
    }
    rule "R64" salience 437 {
        when Order.total > 690
        then Order.discount = Order.discount + 15;
    }
    rule "R65" salience 436 {
        when Order.total > 700
        then Order.discount = Order.discount + 16;
    }
    rule "R66" salience 435 {
        when Order.total > 710
        then Order.discount = Order.discount + 17;
    }
    rule "R67" salience 434 {
        when Order.total > 720
        then Order.discount = Order.discount + 18;
    }
    rule "R68" salience 433 {
        when Order.total > 730
        then Order.discount = Order.discount + 19;
    }
    rule "R69" salience 432 {
        when Order.total > 740
        then Order.discount = Order.discount + 20;
    }
    rule "R70" salience 431 {
        when Order.total > 750
        then Order.discount = Order.discount + 21;
    }
    rule "R71" salience 430 {
        when Order.total > 760
        then Order.discount = Order.discount + 22;
    }
    rule "R72" salience 429 {
        when Order.total > 770
        then Order.discount = Order.discount + 23;
    }
    rule "R73" salience 428 {
        when Order.total > 780
        then Order.discount = Order.discount + 24;
    }
    rule "R74" salience 427 {
        when Order.total > 790
        then Order.discount = Order.discount + 25;
    }
    rule "R75" salience 426 {
        when Order.total > 800
        then Order.discount = Order.discount + 26;
    }
    rule "R76" salience 425 {
        when Order.total > 810
        then Order.discount = Order.discount + 27;
    }
    rule "R77" salience 424 {
        when Order.total > 820
        then Order.discount = Order.discount + 28;
    }
    rule "R78" salience 423 {
        when Order.total > 830
        then Order.discount = Order.discount + 29;
    }
    rule "R79" salience 422 {
        when Order.total > 840
        then Order.discount = Order.discount + 30;
    }
    rule "R80" salience 421 {
        when Order.total > 850
        then Order.discount = Order.discount + 31;
    }
    rule "R81" salience 420 {
        when Order.total > 860
        then Order.discount = Order.discount + 32;
    }
    rule "R82" salience 419 {
        when Order.total > 870
        then Order.discount = Order.discount + 33;
    }
    rule "R83" salience 418 {
        when Order.total > 880
        then Order.discount = Order.discount + 34;
    }
    rule "R84" salience 417 {
        when Order.total > 890
        then Order.discount = Order.discount + 35;
    }
    rule "R85" salience 416 {
        when Order.total > 900
        then Order.discount = Order.discount + 36;
    }
    rule "R86" salience 415 {
        when Order.total > 910
        then Order.discount = Order.discount + 37;
    }
    rule "R87" salience 414 {
        when Order.total > 920
        then Order.discount = Order.discount + 38;
    }
    rule "R88" salience 413 {
        when Order.total > 930
        then Order.discount = Order.discount + 39;
    }
    rule "R89" salience 412 {
        when Order.total > 940
        then Order.discount = Order.discount + 40;
    }
    rule "R90" salience 411 {
        when Order.total > 950
        then Order.discount = Order.discount + 41;
    }
    rule "R91" salience 410 {
        when Order.total > 960
        then Order.discount = Order.discount + 42;
    }
    rule "R92" salience 409 {
        when Order.total > 970
        then Order.discount = Order.discount + 43;
    }
    rule "R93" salience 408 {
        when Order.total > 980
        then Order.discount = Order.discount + 44;
    }
    rule "R94" salience 407 {
        when Order.total > 990
        then Order.discount = Order.discount + 45;
    }
    rule "R95" salience 406 {
        when Order.total > 1000
        then Order.discount = Order.discount + 46;
    }
    rule "R96" salience 405 {
        when Order.total > 1010
        then Order.discount = Order.discount + 47;
    }
    rule "R97" salience 404 {
        when Order.total > 1020
        then Order.discount = Order.discount + 48;
    }
    rule "R98" salience 403 {
        when Order.total > 1030
        then Order.discount = Order.discount + 49;
    }
    rule "R99" salience 402 {
        when Order.total > 1040
        then Order.discount = Order.discount + 50;
    }
    rule "R100" salience 401 {
        when Order.total > 1050
        then Order.discount = Order.discount + 1;
    }
    rule "R101" salience 400 {
        when Order.total > 1060
        then Order.discount = Order.discount + 2;
    }
    rule "R102" salience 399 {
        when Order.total > 1070
        then Order.discount = Order.discount + 3;
    }
    rule "R103" salience 398 {
        when Order.total > 1080
        then Order.discount = Order.discount + 4;
    }
    rule "R104" salience 397 {
        when Order.total > 1090
        then Order.discount = Order.discount + 5;
    }
    rule "R105" salience 396 {
        when Order.total > 1100
        then Order.discount = Order.discount + 6;
    }
    rule "R106" salience 395 {
        when Order.total > 1110
        then Order.discount = Order.discount + 7;
    }
    rule "R107" salience 394 {
        when Order.total > 1120
        then Order.discount = Order.discount + 8;
    }
    rule "R108" salience 393 {
        when Order.total > 1130
        then Order.discount = Order.discount + 9;
    }
    rule "R109" salience 392 {
        when Order.total > 1140
        then Order.discount = Order.discount + 10;
    }
    rule "R110" salience 391 {
        when Order.total > 1150
        then Order.discount = Order.discount + 11;
    }
    rule "R111" salience 390 {
        when Order.total > 1160
        then Order.discount = Order.discount + 12;
    }
    rule "R112" salience 389 {
        when Order.total > 1170
        then Order.discount = Order.discount + 13;
    }
    rule "R113" salience 388 {
        when Order.total > 1180
        then Order.discount = Order.discount + 14;
    }
    rule "R114" salience 387 {
        when Order.total > 1190
        then Order.discount = Order.discount + 15;
    }
    rule "R115" salience 386 {
        when Order.total > 1200
        then Order.discount = Order.discount + 16;
    }
    rule "R116" salience 385 {
        when Order.total > 1210
        then Order.discount = Order.discount + 17;
    }
    rule "R117" salience 384 {
        when Order.total > 1220
        then Order.discount = Order.discount + 18;
    }
    rule "R118" salience 383 {
        when Order.total > 1230
        then Order.discount = Order.discount + 19;
    }
    rule "R119" salience 382 {
        when Order.total > 1240
        then Order.discount = Order.discount + 20;
    }
    rule "R120" salience 381 {
        when Order.total > 1250
        then Order.discount = Order.discount + 21;
    }
    rule "R121" salience 380 {
        when Order.total > 1260
        then Order.discount = Order.discount + 22;
    }
    rule "R122" salience 379 {
        when Order.total > 1270
        then Order.discount = Order.discount + 23;
    }
    rule "R123" salience 378 {
        when Order.total > 1280
        then Order.discount = Order.discount + 24;
    }
    rule "R124" salience 377 {
        when Order.total > 1290
        then Order.discount = Order.discount + 25;
    }
    rule "R125" salience 376 {
        when Order.total > 1300
        then Order.discount = Order.discount + 26;
    }
    rule "R126" salience 375 {
        when Order.total > 1310
        then Order.discount = Order.discount + 27;
    }
    rule "R127" salience 374 {
        when Order.total > 1320
        then Order.discount = Order.discount + 28;
    }
    rule "R128" salience 373 {
        when Order.total > 1330
        then Order.discount = Order.discount + 29;
    }
    rule "R129" salience 372 {
        when Order.total > 1340
        then Order.discount = Order.discount + 30;
    }
    rule "R130" salience 371 {
        when Order.total > 1350
        then Order.discount = Order.discount + 31;
    }
    rule "R131" salience 370 {
        when Order.total > 1360
        then Order.discount = Order.discount + 32;
    }
    rule "R132" salience 369 {
        when Order.total > 1370
        then Order.discount = Order.discount + 33;
    }
    rule "R133" salience 368 {
        when Order.total > 1380
        then Order.discount = Order.discount + 34;
    }
    rule "R134" salience 367 {
        when Order.total > 1390
        then Order.discount = Order.discount + 35;
    }
    rule "R135" salience 366 {
        when Order.total > 1400
        then Order.discount = Order.discount + 36;
    }
    rule "R136" salience 365 {
        when Order.total > 1410
        then Order.discount = Order.discount + 37;
    }
    rule "R137" salience 364 {
        when Order.total > 1420
        then Order.discount = Order.discount + 38;
    }
    rule "R138" salience 363 {
        when Order.total > 1430
        then Order.discount = Order.discount + 39;
    }
    rule "R139" salience 362 {
        when Order.total > 1440
        then Order.discount = Order.discount + 40;
    }
    rule "R140" salience 361 {
        when Order.total > 1450
        then Order.discount = Order.discount + 41;
    }
    rule "R141" salience 360 {
        when Order.total > 1460
        then Order.discount = Order.discount + 42;
    }
    rule "R142" salience 359 {
        when Order.total > 1470
        then Order.discount = Order.discount + 43;
    }
    rule "R143" salience 358 {
        when Order.total > 1480
        then Order.discount = Order.discount + 44;
    }
    rule "R144" salience 357 {
        when Order.total > 1490
        then Order.discount = Order.discount + 45;
    }
    rule "R145" salience 356 {
        when Order.total > 1500
        then Order.discount = Order.discount + 46;
    }
    rule "R146" salience 355 {
        when Order.total > 1510
        then Order.discount = Order.discount + 47;
    }
    rule "R147" salience 354 {
        when Order.total > 1520
        then Order.discount = Order.discount + 48;
    }
    rule "R148" salience 353 {
        when Order.total > 1530
        then Order.discount = Order.discount + 49;
    }
    rule "R149" salience 352 {
        when Order.total > 1540
        then Order.discount = Order.discount + 50;
    }
    rule "R150" salience 351 {
        when Order.total > 1550
        then Order.discount = Order.discount + 1;
    }
    rule "R151" salience 350 {
        when Order.total > 1560
        then Order.discount = Order.discount + 2;
    }
    rule "R152" salience 349 {
        when Order.total > 1570
        then Order.discount = Order.discount + 3;
    }
    rule "R153" salience 348 {
        when Order.total > 1580
        then Order.discount = Order.discount + 4;
    }
    rule "R154" salience 347 {
        when Order.total > 1590
        then Order.discount = Order.discount + 5;
    }
    rule "R155" salience 346 {
        when Order.total > 1600
        then Order.discount = Order.discount + 6;
    }
    rule "R156" salience 345 {
        when Order.total > 1610
        then Order.discount = Order.discount + 7;
    }
    rule "R157" salience 344 {
        when Order.total > 1620
        then Order.discount = Order.discount + 8;
    }
    rule "R158" salience 343 {
        when Order.total > 1630
        then Order.discount = Order.discount + 9;
    }
    rule "R159" salience 342 {
        when Order.total > 1640
        then Order.discount = Order.discount + 10;
    }
    rule "R160" salience 341 {
        when Order.total > 1650
        then Order.discount = Order.discount + 11;
    }
    rule "R161" salience 340 {
        when Order.total > 1660
        then Order.discount = Order.discount + 12;
    }
    rule "R162" salience 339 {
        when Order.total > 1670
        then Order.discount = Order.discount + 13;
    }
    rule "R163" salience 338 {
        when Order.total > 1680
        then Order.discount = Order.discount + 14;
    }
    rule "R164" salience 337 {
        when Order.total > 1690
        then Order.discount = Order.discount + 15;
    }
    rule "R165" salience 336 {
        when Order.total > 1700
        then Order.discount = Order.discount + 16;
    }
    rule "R166" salience 335 {
        when Order.total > 1710
        then Order.discount = Order.discount + 17;
    }
    rule "R167" salience 334 {
        when Order.total > 1720
        then Order.discount = Order.discount + 18;
    }
    rule "R168" salience 333 {
        when Order.total > 1730
        then Order.discount = Order.discount + 19;
    }
    rule "R169" salience 332 {
        when Order.total > 1740
        then Order.discount = Order.discount + 20;
    }
    rule "R170" salience 331 {
        when Order.total > 1750
        then Order.discount = Order.discount + 21;
    }
    rule "R171" salience 330 {
        when Order.total > 1760
        then Order.discount = Order.discount + 22;
    }
    rule "R172" salience 329 {
        when Order.total > 1770
        then Order.discount = Order.discount + 23;
    }
    rule "R173" salience 328 {
        when Order.total > 1780
        then Order.discount = Order.discount + 24;
    }
    rule "R174" salience 327 {
        when Order.total > 1790
        then Order.discount = Order.discount + 25;
    }
    rule "R175" salience 326 {
        when Order.total > 1800
        then Order.discount = Order.discount + 26;
    }
    rule "R176" salience 325 {
        when Order.total > 1810
        then Order.discount = Order.discount + 27;
    }
    rule "R177" salience 324 {
        when Order.total > 1820
        then Order.discount = Order.discount + 28;
    }
    rule "R178" salience 323 {
        when Order.total > 1830
        then Order.discount = Order.discount + 29;
    }
    rule "R179" salience 322 {
        when Order.total > 1840
        then Order.discount = Order.discount + 30;
    }
    rule "R180" salience 321 {
        when Order.total > 1850
        then Order.discount = Order.discount + 31;
    }
    rule "R181" salience 320 {
        when Order.total > 1860
        then Order.discount = Order.discount + 32;
    }
    rule "R182" salience 319 {
        when Order.total > 1870
        then Order.discount = Order.discount + 33;
    }
    rule "R183" salience 318 {
        when Order.total > 1880
        then Order.discount = Order.discount + 34;
    }
    rule "R184" salience 317 {
        when Order.total > 1890
        then Order.discount = Order.discount + 35;
    }
    rule "R185" salience 316 {
        when Order.total > 1900
        then Order.discount = Order.discount + 36;
    }
    rule "R186" salience 315 {
        when Order.total > 1910
        then Order.discount = Order.discount + 37;
    }
    rule "R187" salience 314 {
        when Order.total > 1920
        then Order.discount = Order.discount + 38;
    }
    rule "R188" salience 313 {
        when Order.total > 1930
        then Order.discount = Order.discount + 39;
    }
    rule "R189" salience 312 {
        when Order.total > 1940
        then Order.discount = Order.discount + 40;
    }
    rule "R190" salience 311 {
        when Order.total > 1950
        then Order.discount = Order.discount + 41;
    }
    rule "R191" salience 310 {
        when Order.total > 1960
        then Order.discount = Order.discount + 42;
    }
    rule "R192" salience 309 {
        when Order.total > 1970
        then Order.discount = Order.discount + 43;
    }
    rule "R193" salience 308 {
        when Order.total > 1980
        then Order.discount = Order.discount + 44;
    }
    rule "R194" salience 307 {
        when Order.total > 1990
        then Order.discount = Order.discount + 45;
    }
    rule "R195" salience 306 {
        when Order.total > 2000
        then Order.discount = Order.discount + 46;
    }
    rule "R196" salience 305 {
        when Order.total > 2010
        then Order.discount = Order.discount + 47;
    }
    rule "R197" salience 304 {
        when Order.total > 2020
        then Order.discount = Order.discount + 48;
    }
    rule "R198" salience 303 {
        when Order.total > 2030
        then Order.discount = Order.discount + 49;
    }
    rule "R199" salience 302 {
        when Order.total > 2040
        then Order.discount = Order.discount + 50;
    }
    rule "R200" salience 301 {
        when Order.total > 2050
        then Order.discount = Order.discount + 1;
    }
    rule "R201" salience 300 {
        when Order.total > 2060
        then Order.discount = Order.discount + 2;
    }
    rule "R202" salience 299 {
        when Order.total > 2070
        then Order.discount = Order.discount + 3;
    }
    rule "R203" salience 298 {
        when Order.total > 2080
        then Order.discount = Order.discount + 4;
    }
    rule "R204" salience 297 {
        when Order.total > 2090
        then Order.discount = Order.discount + 5;
    }
    rule "R205" salience 296 {
        when Order.total > 2100
        then Order.discount = Order.discount + 6;
    }
    rule "R206" salience 295 {
        when Order.total > 2110
        then Order.discount = Order.discount + 7;
    }
    rule "R207" salience 294 {
        when Order.total > 2120
        then Order.discount = Order.discount + 8;
    }
    rule "R208" salience 293 {
        when Order.total > 2130
        then Order.discount = Order.discount + 9;
    }
    rule "R209" salience 292 {
        when Order.total > 2140
        then Order.discount = Order.discount + 10;
    }
    rule "R210" salience 291 {
        when Order.total > 2150
        then Order.discount = Order.discount + 11;
    }
    rule "R211" salience 290 {
        when Order.total > 2160
        then Order.discount = Order.discount + 12;
    }
    rule "R212" salience 289 {
        when Order.total > 2170
        then Order.discount = Order.discount + 13;
    }
    rule "R213" salience 288 {
        when Order.total > 2180
        then Order.discount = Order.discount + 14;
    }
    rule "R214" salience 287 {
        when Order.total > 2190
        then Order.discount = Order.discount + 15;
    }
    rule "R215" salience 286 {
        when Order.total > 2200
        then Order.discount = Order.discount + 16;
    }
    rule "R216" salience 285 {
        when Order.total > 2210
        then Order.discount = Order.discount + 17;
    }
    rule "R217" salience 284 {
        when Order.total > 2220
        then Order.discount = Order.discount + 18;
    }
    rule "R218" salience 283 {
        when Order.total > 2230
        then Order.discount = Order.discount + 19;
    }
    rule "R219" salience 282 {
        when Order.total > 2240
        then Order.discount = Order.discount + 20;
    }
    rule "R220" salience 281 {
        when Order.total > 2250
        then Order.discount = Order.discount + 21;
    }
    rule "R221" salience 280 {
        when Order.total > 2260
        then Order.discount = Order.discount + 22;
    }
    rule "R222" salience 279 {
        when Order.total > 2270
        then Order.discount = Order.discount + 23;
    }
    rule "R223" salience 278 {
        when Order.total > 2280
        then Order.discount = Order.discount + 24;
    }
    rule "R224" salience 277 {
        when Order.total > 2290
        then Order.discount = Order.discount + 25;
    }
    rule "R225" salience 276 {
        when Order.total > 2300
        then Order.discount = Order.discount + 26;
    }
    rule "R226" salience 275 {
        when Order.total > 2310
        then Order.discount = Order.discount + 27;
    }
    rule "R227" salience 274 {
        when Order.total > 2320
        then Order.discount = Order.discount + 28;
    }
    rule "R228" salience 273 {
        when Order.total > 2330
        then Order.discount = Order.discount + 29;
    }
    rule "R229" salience 272 {
        when Order.total > 2340
        then Order.discount = Order.discount + 30;
    }
    rule "R230" salience 271 {
        when Order.total > 2350
        then Order.discount = Order.discount + 31;
    }
    rule "R231" salience 270 {
        when Order.total > 2360
        then Order.discount = Order.discount + 32;
    }
    rule "R232" salience 269 {
        when Order.total > 2370
        then Order.discount = Order.discount + 33;
    }
    rule "R233" salience 268 {
        when Order.total > 2380
        then Order.discount = Order.discount + 34;
    }
    rule "R234" salience 267 {
        when Order.total > 2390
        then Order.discount = Order.discount + 35;
    }
    rule "R235" salience 266 {
        when Order.total > 2400
        then Order.discount = Order.discount + 36;
    }
    rule "R236" salience 265 {
        when Order.total > 2410
        then Order.discount = Order.discount + 37;
    }
    rule "R237" salience 264 {
        when Order.total > 2420
        then Order.discount = Order.discount + 38;
    }
    rule "R238" salience 263 {
        when Order.total > 2430
        then Order.discount = Order.discount + 39;
    }
    rule "R239" salience 262 {
        when Order.total > 2440
        then Order.discount = Order.discount + 40;
    }
    rule "R240" salience 261 {
        when Order.total > 2450
        then Order.discount = Order.discount + 41;
    }
    rule "R241" salience 260 {
        when Order.total > 2460
        then Order.discount = Order.discount + 42;
    }
    rule "R242" salience 259 {
        when Order.total > 2470
        then Order.discount = Order.discount + 43;
    }
    rule "R243" salience 258 {
        when Order.total > 2480
        then Order.discount = Order.discount + 44;
    }
    rule "R244" salience 257 {
        when Order.total > 2490
        then Order.discount = Order.discount + 45;
    }
    rule "R245" salience 256 {
        when Order.total > 2500
        then Order.discount = Order.discount + 46;
    }
    rule "R246" salience 255 {
        when Order.total > 2510
        then Order.discount = Order.discount + 47;
    }
    rule "R247" salience 254 {
        when Order.total > 2520
        then Order.discount = Order.discount + 48;
    }
    rule "R248" salience 253 {
        when Order.total > 2530
        then Order.discount = Order.discount + 49;
    }
    rule "R249" salience 252 {
        when Order.total > 2540
        then Order.discount = Order.discount + 50;
    }
    rule "R250" salience 251 {
        when Order.total > 2550
        then Order.discount = Order.discount + 1;
    }
    rule "R251" salience 250 {
        when Order.total > 2560
        then Order.discount = Order.discount + 2;
    }
    rule "R252" salience 249 {
        when Order.total > 2570
        then Order.discount = Order.discount + 3;
    }
    rule "R253" salience 248 {
        when Order.total > 2580
        then Order.discount = Order.discount + 4;
    }
    rule "R254" salience 247 {
        when Order.total > 2590
        then Order.discount = Order.discount + 5;
    }
    rule "R255" salience 246 {
        when Order.total > 2600
        then Order.discount = Order.discount + 6;
    }
    rule "R256" salience 245 {
        when Order.total > 2610
        then Order.discount = Order.discount + 7;
    }
    rule "R257" salience 244 {
        when Order.total > 2620
        then Order.discount = Order.discount + 8;
    }
    rule "R258" salience 243 {
        when Order.total > 2630
        then Order.discount = Order.discount + 9;
    }
    rule "R259" salience 242 {
        when Order.total > 2640
        then Order.discount = Order.discount + 10;
    }
    rule "R260" salience 241 {
        when Order.total > 2650
        then Order.discount = Order.discount + 11;
    }
    rule "R261" salience 240 {
        when Order.total > 2660
        then Order.discount = Order.discount + 12;
    }
    rule "R262" salience 239 {
        when Order.total > 2670
        then Order.discount = Order.discount + 13;
    }
    rule "R263" salience 238 {
        when Order.total > 2680
        then Order.discount = Order.discount + 14;
    }
    rule "R264" salience 237 {
        when Order.total > 2690
        then Order.discount = Order.discount + 15;
    }
    rule "R265" salience 236 {
        when Order.total > 2700
        then Order.discount = Order.discount + 16;
    }
    rule "R266" salience 235 {
        when Order.total > 2710
        then Order.discount = Order.discount + 17;
    }
    rule "R267" salience 234 {
        when Order.total > 2720
        then Order.discount = Order.discount + 18;
    }
    rule "R268" salience 233 {
        when Order.total > 2730
        then Order.discount = Order.discount + 19;
    }
    rule "R269" salience 232 {
        when Order.total > 2740
        then Order.discount = Order.discount + 20;
    }
    rule "R270" salience 231 {
        when Order.total > 2750
        then Order.discount = Order.discount + 21;
    }
    rule "R271" salience 230 {
        when Order.total > 2760
        then Order.discount = Order.discount + 22;
    }
    rule "R272" salience 229 {
        when Order.total > 2770
        then Order.discount = Order.discount + 23;
    }
    rule "R273" salience 228 {
        when Order.total > 2780
        then Order.discount = Order.discount + 24;
    }
    rule "R274" salience 227 {
        when Order.total > 2790
        then Order.discount = Order.discount + 25;
    }
    rule "R275" salience 226 {
        when Order.total > 2800
        then Order.discount = Order.discount + 26;
    }
    rule "R276" salience 225 {
        when Order.total > 2810
        then Order.discount = Order.discount + 27;
    }
    rule "R277" salience 224 {
        when Order.total > 2820
        then Order.discount = Order.discount + 28;
    }
    rule "R278" salience 223 {
        when Order.total > 2830
        then Order.discount = Order.discount + 29;
    }
    rule "R279" salience 222 {
        when Order.total > 2840
        then Order.discount = Order.discount + 30;
    }
    rule "R280" salience 221 {
        when Order.total > 2850
        then Order.discount = Order.discount + 31;
    }
    rule "R281" salience 220 {
        when Order.total > 2860
        then Order.discount = Order.discount + 32;
    }
    rule "R282" salience 219 {
        when Order.total > 2870
        then Order.discount = Order.discount + 33;
    }
    rule "R283" salience 218 {
        when Order.total > 2880
        then Order.discount = Order.discount + 34;
    }
    rule "R284" salience 217 {
        when Order.total > 2890
        then Order.discount = Order.discount + 35;
    }
    rule "R285" salience 216 {
        when Order.total > 2900
        then Order.discount = Order.discount + 36;
    }
    rule "R286" salience 215 {
        when Order.total > 2910
        then Order.discount = Order.discount + 37;
    }
    rule "R287" salience 214 {
        when Order.total > 2920
        then Order.discount = Order.discount + 38;
    }
    rule "R288" salience 213 {
        when Order.total > 2930
        then Order.discount = Order.discount + 39;
    }
    rule "R289" salience 212 {
        when Order.total > 2940
        then Order.discount = Order.discount + 40;
    }
    rule "R290" salience 211 {
        when Order.total > 2950
        then Order.discount = Order.discount + 41;
    }
    rule "R291" salience 210 {
        when Order.total > 2960
        then Order.discount = Order.discount + 42;
    }
    rule "R292" salience 209 {
        when Order.total > 2970
        then Order.discount = Order.discount + 43;
    }
    rule "R293" salience 208 {
        when Order.total > 2980
        then Order.discount = Order.discount + 44;
    }
    rule "R294" salience 207 {
        when Order.total > 2990
        then Order.discount = Order.discount + 45;
    }
    rule "R295" salience 206 {
        when Order.total > 3000
        then Order.discount = Order.discount + 46;
    }
    rule "R296" salience 205 {
        when Order.total > 3010
        then Order.discount = Order.discount + 47;
    }
    rule "R297" salience 204 {
        when Order.total > 3020
        then Order.discount = Order.discount + 48;
    }
    rule "R298" salience 203 {
        when Order.total > 3030
        then Order.discount = Order.discount + 49;
    }
    rule "R299" salience 202 {
        when Order.total > 3040
        then Order.discount = Order.discount + 50;
    }
    rule "R300" salience 201 {
        when Order.total > 3050
        then Order.discount = Order.discount + 1;
    }
    rule "R301" salience 200 {
        when Order.total > 3060
        then Order.discount = Order.discount + 2;
    }
    rule "R302" salience 199 {
        when Order.total > 3070
        then Order.discount = Order.discount + 3;
    }
    rule "R303" salience 198 {
        when Order.total > 3080
        then Order.discount = Order.discount + 4;
    }
    rule "R304" salience 197 {
        when Order.total > 3090
        then Order.discount = Order.discount + 5;
    }
    rule "R305" salience 196 {
        when Order.total > 3100
        then Order.discount = Order.discount + 6;
    }
    rule "R306" salience 195 {
        when Order.total > 3110
        then Order.discount = Order.discount + 7;
    }
    rule "R307" salience 194 {
        when Order.total > 3120
        then Order.discount = Order.discount + 8;
    }
    rule "R308" salience 193 {
        when Order.total > 3130
        then Order.discount = Order.discount + 9;
    }
    rule "R309" salience 192 {
        when Order.total > 3140
        then Order.discount = Order.discount + 10;
    }
    rule "R310" salience 191 {
        when Order.total > 3150
        then Order.discount = Order.discount + 11;
    }
    rule "R311" salience 190 {
        when Order.total > 3160
        then Order.discount = Order.discount + 12;
    }
    rule "R312" salience 189 {
        when Order.total > 3170
        then Order.discount = Order.discount + 13;
    }
    rule "R313" salience 188 {
        when Order.total > 3180
        then Order.discount = Order.discount + 14;
    }
    rule "R314" salience 187 {
        when Order.total > 3190
        then Order.discount = Order.discount + 15;
    }
    rule "R315" salience 186 {
        when Order.total > 3200
        then Order.discount = Order.discount + 16;
    }
    rule "R316" salience 185 {
        when Order.total > 3210
        then Order.discount = Order.discount + 17;
    }
    rule "R317" salience 184 {
        when Order.total > 3220
        then Order.discount = Order.discount + 18;
    }
    rule "R318" salience 183 {
        when Order.total > 3230
        then Order.discount = Order.discount + 19;
    }
    rule "R319" salience 182 {
        when Order.total > 3240
        then Order.discount = Order.discount + 20;
    }
    rule "R320" salience 181 {
        when Order.total > 3250
        then Order.discount = Order.discount + 21;
    }
    rule "R321" salience 180 {
        when Order.total > 3260
        then Order.discount = Order.discount + 22;
    }
    rule "R322" salience 179 {
        when Order.total > 3270
        then Order.discount = Order.discount + 23;
    }
    rule "R323" salience 178 {
        when Order.total > 3280
        then Order.discount = Order.discount + 24;
    }
    rule "R324" salience 177 {
        when Order.total > 3290
        then Order.discount = Order.discount + 25;
    }
    rule "R325" salience 176 {
        when Order.total > 3300
        then Order.discount = Order.discount + 26;
    }
    rule "R326" salience 175 {
        when Order.total > 3310
        then Order.discount = Order.discount + 27;
    }
    rule "R327" salience 174 {
        when Order.total > 3320
        then Order.discount = Order.discount + 28;
    }
    rule "R328" salience 173 {
        when Order.total > 3330
        then Order.discount = Order.discount + 29;
    }
    rule "R329" salience 172 {
        when Order.total > 3340
        then Order.discount = Order.discount + 30;
    }
    rule "R330" salience 171 {
        when Order.total > 3350
        then Order.discount = Order.discount + 31;
    }
    rule "R331" salience 170 {
        when Order.total > 3360
        then Order.discount = Order.discount + 32;
    }
    rule "R332" salience 169 {
        when Order.total > 3370
        then Order.discount = Order.discount + 33;
    }
    rule "R333" salience 168 {
        when Order.total > 3380
        then Order.discount = Order.discount + 34;
    }
    rule "R334" salience 167 {
        when Order.total > 3390
        then Order.discount = Order.discount + 35;
    }
    rule "R335" salience 166 {
        when Order.total > 3400
        then Order.discount = Order.discount + 36;
    }
    rule "R336" salience 165 {
        when Order.total > 3410
        then Order.discount = Order.discount + 37;
    }
    rule "R337" salience 164 {
        when Order.total > 3420
        then Order.discount = Order.discount + 38;
    }
    rule "R338" salience 163 {
        when Order.total > 3430
        then Order.discount = Order.discount + 39;
    }
    rule "R339" salience 162 {
        when Order.total > 3440
        then Order.discount = Order.discount + 40;
    }
    rule "R340" salience 161 {
        when Order.total > 3450
        then Order.discount = Order.discount + 41;
    }
    rule "R341" salience 160 {
        when Order.total > 3460
        then Order.discount = Order.discount + 42;
    }
    rule "R342" salience 159 {
        when Order.total > 3470
        then Order.discount = Order.discount + 43;
    }
    rule "R343" salience 158 {
        when Order.total > 3480
        then Order.discount = Order.discount + 44;
    }
    rule "R344" salience 157 {
        when Order.total > 3490
        then Order.discount = Order.discount + 45;
    }
    rule "R345" salience 156 {
        when Order.total > 3500
        then Order.discount = Order.discount + 46;
    }
    rule "R346" salience 155 {
        when Order.total > 3510
        then Order.discount = Order.discount + 47;
    }
    rule "R347" salience 154 {
        when Order.total > 3520
        then Order.discount = Order.discount + 48;
    }
    rule "R348" salience 153 {
        when Order.total > 3530
        then Order.discount = Order.discount + 49;
    }
    rule "R349" salience 152 {
        when Order.total > 3540
        then Order.discount = Order.discount + 50;
    }
    rule "R350" salience 151 {
        when Order.total > 3550
        then Order.discount = Order.discount + 1;
    }
    rule "R351" salience 150 {
        when Order.total > 3560
        then Order.discount = Order.discount + 2;
    }
    rule "R352" salience 149 {
        when Order.total > 3570
        then Order.discount = Order.discount + 3;
    }
    rule "R353" salience 148 {
        when Order.total > 3580
        then Order.discount = Order.discount + 4;
    }
    rule "R354" salience 147 {
        when Order.total > 3590
        then Order.discount = Order.discount + 5;
    }
    rule "R355" salience 146 {
        when Order.total > 3600
        then Order.discount = Order.discount + 6;
    }
    rule "R356" salience 145 {
        when Order.total > 3610
        then Order.discount = Order.discount + 7;
    }
    rule "R357" salience 144 {
        when Order.total > 3620
        then Order.discount = Order.discount + 8;
    }
    rule "R358" salience 143 {
        when Order.total > 3630
        then Order.discount = Order.discount + 9;
    }
    rule "R359" salience 142 {
        when Order.total > 3640
        then Order.discount = Order.discount + 10;
    }
    rule "R360" salience 141 {
        when Order.total > 3650
        then Order.discount = Order.discount + 11;
    }
    rule "R361" salience 140 {
        when Order.total > 3660
        then Order.discount = Order.discount + 12;
    }
    rule "R362" salience 139 {
        when Order.total > 3670
        then Order.discount = Order.discount + 13;
    }
    rule "R363" salience 138 {
        when Order.total > 3680
        then Order.discount = Order.discount + 14;
    }
    rule "R364" salience 137 {
        when Order.total > 3690
        then Order.discount = Order.discount + 15;
    }
    rule "R365" salience 136 {
        when Order.total > 3700
        then Order.discount = Order.discount + 16;
    }
    rule "R366" salience 135 {
        when Order.total > 3710
        then Order.discount = Order.discount + 17;
    }
    rule "R367" salience 134 {
        when Order.total > 3720
        then Order.discount = Order.discount + 18;
    }
    rule "R368" salience 133 {
        when Order.total > 3730
        then Order.discount = Order.discount + 19;
    }
    rule "R369" salience 132 {
        when Order.total > 3740
        then Order.discount = Order.discount + 20;
    }
    rule "R370" salience 131 {
        when Order.total > 3750
        then Order.discount = Order.discount + 21;
    }
    rule "R371" salience 130 {
        when Order.total > 3760
        then Order.discount = Order.discount + 22;
    }
    rule "R372" salience 129 {
        when Order.total > 3770
        then Order.discount = Order.discount + 23;
    }
    rule "R373" salience 128 {
        when Order.total > 3780
        then Order.discount = Order.discount + 24;
    }
    rule "R374" salience 127 {
        when Order.total > 3790
        then Order.discount = Order.discount + 25;
    }
    rule "R375" salience 126 {
        when Order.total > 3800
        then Order.discount = Order.discount + 26;
    }
    rule "R376" salience 125 {
        when Order.total > 3810
        then Order.discount = Order.discount + 27;
    }
    rule "R377" salience 124 {
        when Order.total > 3820
        then Order.discount = Order.discount + 28;
    }
    rule "R378" salience 123 {
        when Order.total > 3830
        then Order.discount = Order.discount + 29;
    }
    rule "R379" salience 122 {
        when Order.total > 3840
        then Order.discount = Order.discount + 30;
    }
    rule "R380" salience 121 {
        when Order.total > 3850
        then Order.discount = Order.discount + 31;
    }
    rule "R381" salience 120 {
        when Order.total > 3860
        then Order.discount = Order.discount + 32;
    }
    rule "R382" salience 119 {
        when Order.total > 3870
        then Order.discount = Order.discount + 33;
    }
    rule "R383" salience 118 {
        when Order.total > 3880
        then Order.discount = Order.discount + 34;
    }
    rule "R384" salience 117 {
        when Order.total > 3890
        then Order.discount = Order.discount + 35;
    }
    rule "R385" salience 116 {
        when Order.total > 3900
        then Order.discount = Order.discount + 36;
    }
    rule "R386" salience 115 {
        when Order.total > 3910
        then Order.discount = Order.discount + 37;
    }
    rule "R387" salience 114 {
        when Order.total > 3920
        then Order.discount = Order.discount + 38;
    }
    rule "R388" salience 113 {
        when Order.total > 3930
        then Order.discount = Order.discount + 39;
    }
    rule "R389" salience 112 {
        when Order.total > 3940
        then Order.discount = Order.discount + 40;
    }
    rule "R390" salience 111 {
        when Order.total > 3950
        then Order.discount = Order.discount + 41;
    }
    rule "R391" salience 110 {
        when Order.total > 3960
        then Order.discount = Order.discount + 42;
    }
    rule "R392" salience 109 {
        when Order.total > 3970
        then Order.discount = Order.discount + 43;
    }
    rule "R393" salience 108 {
        when Order.total > 3980
        then Order.discount = Order.discount + 44;
    }
    rule "R394" salience 107 {
        when Order.total > 3990
        then Order.discount = Order.discount + 45;
    }
    rule "R395" salience 106 {
        when Order.total > 4000
        then Order.discount = Order.discount + 46;
    }
    rule "R396" salience 105 {
        when Order.total > 4010
        then Order.discount = Order.discount + 47;
    }
    rule "R397" salience 104 {
        when Order.total > 4020
        then Order.discount = Order.discount + 48;
    }
    rule "R398" salience 103 {
        when Order.total > 4030
        then Order.discount = Order.discount + 49;
    }
    rule "R399" salience 102 {
        when Order.total > 4040
        then Order.discount = Order.discount + 50;
    }
    rule "R400" salience 101 {
        when Order.total > 4050
        then Order.discount = Order.discount + 1;
    }
    rule "R401" salience 100 {
        when Order.total > 4060
        then Order.discount = Order.discount + 2;
    }
    rule "R402" salience 99 {
        when Order.total > 4070
        then Order.discount = Order.discount + 3;
    }
    rule "R403" salience 98 {
        when Order.total > 4080
        then Order.discount = Order.discount + 4;
    }
    rule "R404" salience 97 {
        when Order.total > 4090
        then Order.discount = Order.discount + 5;
    }
    rule "R405" salience 96 {
        when Order.total > 4100
        then Order.discount = Order.discount + 6;
    }
    rule "R406" salience 95 {
        when Order.total > 4110
        then Order.discount = Order.discount + 7;
    }
    rule "R407" salience 94 {
        when Order.total > 4120
        then Order.discount = Order.discount + 8;
    }
    rule "R408" salience 93 {
        when Order.total > 4130
        then Order.discount = Order.discount + 9;
    }
    rule "R409" salience 92 {
        when Order.total > 4140
        then Order.discount = Order.discount + 10;
    }
    rule "R410" salience 91 {
        when Order.total > 4150
        then Order.discount = Order.discount + 11;
    }
    rule "R411" salience 90 {
        when Order.total > 4160
        then Order.discount = Order.discount + 12;
    }
    rule "R412" salience 89 {
        when Order.total > 4170
        then Order.discount = Order.discount + 13;
    }
    rule "R413" salience 88 {
        when Order.total > 4180
        then Order.discount = Order.discount + 14;
    }
    rule "R414" salience 87 {
        when Order.total > 4190
        then Order.discount = Order.discount + 15;
    }
    rule "R415" salience 86 {
        when Order.total > 4200
        then Order.discount = Order.discount + 16;
    }
    rule "R416" salience 85 {
        when Order.total > 4210
        then Order.discount = Order.discount + 17;
    }
    rule "R417" salience 84 {
        when Order.total > 4220
        then Order.discount = Order.discount + 18;
    }
    rule "R418" salience 83 {
        when Order.total > 4230
        then Order.discount = Order.discount + 19;
    }
    rule "R419" salience 82 {
        when Order.total > 4240
        then Order.discount = Order.discount + 20;
    }
    rule "R420" salience 81 {
        when Order.total > 4250
        then Order.discount = Order.discount + 21;
    }
    rule "R421" salience 80 {
        when Order.total > 4260
        then Order.discount = Order.discount + 22;
    }
    rule "R422" salience 79 {
        when Order.total > 4270
        then Order.discount = Order.discount + 23;
    }
    rule "R423" salience 78 {
        when Order.total > 4280
        then Order.discount = Order.discount + 24;
    }
    rule "R424" salience 77 {
        when Order.total > 4290
        then Order.discount = Order.discount + 25;
    }
    rule "R425" salience 76 {
        when Order.total > 4300
        then Order.discount = Order.discount + 26;
    }
    rule "R426" salience 75 {
        when Order.total > 4310
        then Order.discount = Order.discount + 27;
    }
    rule "R427" salience 74 {
        when Order.total > 4320
        then Order.discount = Order.discount + 28;
    }
    rule "R428" salience 73 {
        when Order.total > 4330
        then Order.discount = Order.discount + 29;
    }
    rule "R429" salience 72 {
        when Order.total > 4340
        then Order.discount = Order.discount + 30;
    }
    rule "R430" salience 71 {
        when Order.total > 4350
        then Order.discount = Order.discount + 31;
    }
    rule "R431" salience 70 {
        when Order.total > 4360
        then Order.discount = Order.discount + 32;
    }
    rule "R432" salience 69 {
        when Order.total > 4370
        then Order.discount = Order.discount + 33;
    }
    rule "R433" salience 68 {
        when Order.total > 4380
        then Order.discount = Order.discount + 34;
    }
    rule "R434" salience 67 {
        when Order.total > 4390
        then Order.discount = Order.discount + 35;
    }
    rule "R435" salience 66 {
        when Order.total > 4400
        then Order.discount = Order.discount + 36;
    }
    rule "R436" salience 65 {
        when Order.total > 4410
        then Order.discount = Order.discount + 37;
    }
    rule "R437" salience 64 {
        when Order.total > 4420
        then Order.discount = Order.discount + 38;
    }
    rule "R438" salience 63 {
        when Order.total > 4430
        then Order.discount = Order.discount + 39;
    }
    rule "R439" salience 62 {
        when Order.total > 4440
        then Order.discount = Order.discount + 40;
    }
    rule "R440" salience 61 {
        when Order.total > 4450
        then Order.discount = Order.discount + 41;
    }
    rule "R441" salience 60 {
        when Order.total > 4460
        then Order.discount = Order.discount + 42;
    }
    rule "R442" salience 59 {
        when Order.total > 4470
        then Order.discount = Order.discount + 43;
    }
    rule "R443" salience 58 {
        when Order.total > 4480
        then Order.discount = Order.discount + 44;
    }
    rule "R444" salience 57 {
        when Order.total > 4490
        then Order.discount = Order.discount + 45;
    }
    rule "R445" salience 56 {
        when Order.total > 4500
        then Order.discount = Order.discount + 46;
    }
    rule "R446" salience 55 {
        when Order.total > 4510
        then Order.discount = Order.discount + 47;
    }
    rule "R447" salience 54 {
        when Order.total > 4520
        then Order.discount = Order.discount + 48;
    }
    rule "R448" salience 53 {
        when Order.total > 4530
        then Order.discount = Order.discount + 49;
    }
    rule "R449" salience 52 {
        when Order.total > 4540
        then Order.discount = Order.discount + 50;
    }
    rule "R450" salience 51 {
        when Order.total > 4550
        then Order.discount = Order.discount + 1;
    }
    rule "R451" salience 50 {
        when Order.total > 4560
        then Order.discount = Order.discount + 2;
    }
    rule "R452" salience 49 {
        when Order.total > 4570
        then Order.discount = Order.discount + 3;
    }
    rule "R453" salience 48 {
        when Order.total > 4580
        then Order.discount = Order.discount + 4;
    }
    rule "R454" salience 47 {
        when Order.total > 4590
        then Order.discount = Order.discount + 5;
    }
    rule "R455" salience 46 {
        when Order.total > 4600
        then Order.discount = Order.discount + 6;
    }
    rule "R456" salience 45 {
        when Order.total > 4610
        then Order.discount = Order.discount + 7;
    }
    rule "R457" salience 44 {
        when Order.total > 4620
        then Order.discount = Order.discount + 8;
    }
    rule "R458" salience 43 {
        when Order.total > 4630
        then Order.discount = Order.discount + 9;
    }
    rule "R459" salience 42 {
        when Order.total > 4640
        then Order.discount = Order.discount + 10;
    }
    rule "R460" salience 41 {
        when Order.total > 4650
        then Order.discount = Order.discount + 11;
    }
    rule "R461" salience 40 {
        when Order.total > 4660
        then Order.discount = Order.discount + 12;
    }
    rule "R462" salience 39 {
        when Order.total > 4670
        then Order.discount = Order.discount + 13;
    }
    rule "R463" salience 38 {
        when Order.total > 4680
        then Order.discount = Order.discount + 14;
    }
    rule "R464" salience 37 {
        when Order.total > 4690
        then Order.discount = Order.discount + 15;
    }
    rule "R465" salience 36 {
        when Order.total > 4700
        then Order.discount = Order.discount + 16;
    }
    rule "R466" salience 35 {
        when Order.total > 4710
        then Order.discount = Order.discount + 17;
    }
    rule "R467" salience 34 {
        when Order.total > 4720
        then Order.discount = Order.discount + 18;
    }
    rule "R468" salience 33 {
        when Order.total > 4730
        then Order.discount = Order.discount + 19;
    }
    rule "R469" salience 32 {
        when Order.total > 4740
        then Order.discount = Order.discount + 20;
    }
    rule "R470" salience 31 {
        when Order.total > 4750
        then Order.discount = Order.discount + 21;
    }
    rule "R471" salience 30 {
        when Order.total > 4760
        then Order.discount = Order.discount + 22;
    }
    rule "R472" salience 29 {
        when Order.total > 4770
        then Order.discount = Order.discount + 23;
    }
    rule "R473" salience 28 {
        when Order.total > 4780
        then Order.discount = Order.discount + 24;
    }
    rule "R474" salience 27 {
        when Order.total > 4790
        then Order.discount = Order.discount + 25;
    }
    rule "R475" salience 26 {
        when Order.total > 4800
        then Order.discount = Order.discount + 26;
    }
    rule "R476" salience 25 {
        when Order.total > 4810
        then Order.discount = Order.discount + 27;
    }
    rule "R477" salience 24 {
        when Order.total > 4820
        then Order.discount = Order.discount + 28;
    }
    rule "R478" salience 23 {
        when Order.total > 4830
        then Order.discount = Order.discount + 29;
    }
    rule "R479" salience 22 {
        when Order.total > 4840
        then Order.discount = Order.discount + 30;
    }
    rule "R480" salience 21 {
        when Order.total > 4850
        then Order.discount = Order.discount + 31;
    }
    rule "R481" salience 20 {
        when Order.total > 4860
        then Order.discount = Order.discount + 32;
    }
    rule "R482" salience 19 {
        when Order.total > 4870
        then Order.discount = Order.discount + 33;
    }
    rule "R483" salience 18 {
        when Order.total > 4880
        then Order.discount = Order.discount + 34;
    }
    rule "R484" salience 17 {
        when Order.total > 4890
        then Order.discount = Order.discount + 35;
    }
    rule "R485" salience 16 {
        when Order.total > 4900
        then Order.discount = Order.discount + 36;
    }
    rule "R486" salience 15 {
        when Order.total > 4910
        then Order.discount = Order.discount + 37;
    }
    rule "R487" salience 14 {
        when Order.total > 4920
        then Order.discount = Order.discount + 38;
    }
    rule "R488" salience 13 {
        when Order.total > 4930
        then Order.discount = Order.discount + 39;
    }
    rule "R489" salience 12 {
        when Order.total > 4940
        then Order.discount = Order.discount + 40;
    }
    rule "R490" salience 11 {
        when Order.total > 4950
        then Order.discount = Order.discount + 41;
    }
    rule "R491" salience 10 {
        when Order.total > 4960
        then Order.discount = Order.discount + 42;
    }
    rule "R492" salience 9 {
        when Order.total > 4970
        then Order.discount = Order.discount + 43;
    }
    rule "R493" salience 8 {
        when Order.total > 4980
        then Order.discount = Order.discount + 44;
    }
    rule "R494" salience 7 {
        when Order.total > 4990
        then Order.discount = Order.discount + 45;
    }
    rule "R495" salience 6 {
        when Order.total > 5000
        then Order.discount = Order.discount + 46;
    }
    rule "R496" salience 5 {
        when Order.total > 5010
        then Order.discount = Order.discount + 47;
    }
    rule "R497" salience 4 {
        when Order.total > 5020
        then Order.discount = Order.discount + 48;
    }
    rule "R498" salience 3 {
        when Order.total > 5030
        then Order.discount = Order.discount + 49;
    }
    rule "R499" salience 2 {
        when Order.total > 5040
        then Order.discount = Order.discount + 50;
    }
    rule "R500" salience 1 {
        when Order.total > 5050
        then Order.discount = Order.discount + 1;
    }
')::jsonb;
