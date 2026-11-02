class_name RealWorld
## The real-world region: North America, the North Atlantic and Europe, compressed 1:5 onto the
## game map south of Calderra (New York to London is about 1,100 km). Generated from latitude /
## longitude outlines by tools/geo_real.py; positions are world km (x east, z south) unless noted.

const LON0 := -40.0
const LAT0 := 45.0
const KX := 15743.03        # metres per degree of longitude
const KZ := 22114.80        # metres per degree of latitude
const ORIGIN_Z := 1300000.0
const GRID_X0 := -1360000.0
const GRID_Z0 := 696000.0
const GRID_NX := 289
const GRID_NZ := 142
const CELL := 8000.0

const POLY_NAMES := ["North America", "Baffin Island", "Greenland", "Iceland", "Newfoundland", "Cuba", "Great Britain", "Ireland", "Europe", "Africa"]
const POLYS := [
	[  # North America
		Vector2(-1495.6, 747.1), Vector2(-1464.1, 1012.5), Vector2(-1424.7, 1089.9), Vector2(-1393.3, 1156.3), Vector2(-1346.0, 1200.5), Vector2(-1333.4, 1224.8), Vector2(-1324.0, 1273.5), Vector2(-1322.4, 1337.6),
		Vector2(-1327.1, 1377.4), Vector2(-1319.3, 1421.6), Vector2(-1307.5, 1454.8), Vector2(-1300.7, 1459.2), Vector2(-1299.1, 1468.1), Vector2(-1289.4, 1485.8), Vector2(-1279.9, 1507.9), Vector2(-1268.9, 1530.0),
		Vector2(-1246.8, 1537.7), Vector2(-1236.6, 1542.8), Vector2(-1235.0, 1548.8), Vector2(-1226.4, 1552.1), Vector2(-1215.4, 1572.0), Vector2(-1207.5, 1591.9), Vector2(-1193.3, 1622.9), Vector2(-1168.1, 1676.0),
		Vector2(-1136.6, 1731.2), Vector2(-1100.4, 1788.7), Vector2(-1095.7, 1773.3), Vector2(-1111.5, 1755.6), Vector2(-1133.5, 1702.5), Vector2(-1157.1, 1653.8), Vector2(-1177.6, 1596.3), Vector2(-1149.2, 1605.2),
		Vector2(-1117.8, 1653.8), Vector2(-1094.1, 1698.1), Vector2(-1070.5, 1733.5), Vector2(-1045.3, 1782.1), Vector2(-1028.0, 1830.8), Vector2(-1015.4, 1870.6), Vector2(-976.1, 1899.3), Vector2(-944.6, 1919.2),
		Vector2(-881.6, 1948.0), Vector2(-858.0, 1936.9), Vector2(-858.0, 1892.7), Vector2(-883.2, 1870.6), Vector2(-903.6, 1830.8), Vector2(-909.9, 1802.0), Vector2(-905.2, 1753.4), Vector2(-900.5, 1722.4),
		Vector2(-903.6, 1680.4), Vector2(-881.6, 1662.7), Vector2(-862.7, 1647.2), Vector2(-834.4, 1638.4), Vector2(-802.9, 1649.4), Vector2(-774.6, 1653.8), Vector2(-780.9, 1627.3), Vector2(-755.7, 1622.9),
		Vector2(-732.1, 1622.9), Vector2(-714.7, 1638.4), Vector2(-697.4, 1631.7), Vector2(-677.0, 1651.6), Vector2(-672.2, 1678.2), Vector2(-662.8, 1706.9), Vector2(-654.9, 1722.4), Vector2(-645.5, 1739.0),
		Vector2(-633.7, 1740.1), Vector2(-625.8, 1725.7), Vector2(-625.8, 1704.7), Vector2(-636.8, 1667.1), Vector2(-648.6, 1636.1), Vector2(-651.8, 1622.9), Vector2(-645.5, 1591.9), Vector2(-629.7, 1572.0),
		Vector2(-607.7, 1547.7), Vector2(-596.7, 1541.1), Vector2(-576.2, 1527.8), Vector2(-558.9, 1516.7), Vector2(-562.0, 1488.0), Vector2(-566.7, 1478.0), Vector2(-560.5, 1461.4), Vector2(-552.6, 1446.0),
		Vector2(-551.8, 1437.1), Vector2(-549.4, 1433.8), Vector2(-541.6, 1423.8), Vector2(-535.3, 1408.4), Vector2(-534.5, 1400.6), Vector2(-527.4, 1398.4), Vector2(-513.2, 1392.9), Vector2(-501.6, 1386.9),
		Vector2(-508.5, 1385.1), Vector2(-494.3, 1378.5), Vector2(-482.5, 1376.3), Vector2(-471.5, 1374.1), Vector2(-473.1, 1365.2), Vector2(-481.7, 1366.3), Vector2(-487.2, 1359.0), Vector2(-484.1, 1352.0),
		Vector2(-483.3, 1342.0), Vector2(-475.4, 1329.9), Vector2(-456.5, 1322.1), Vector2(-444.0, 1314.4), Vector2(-425.1, 1304.4), Vector2(-409.3, 1294.5), Vector2(-385.7, 1284.5), Vector2(-404.6, 1306.6),
		Vector2(-410.9, 1326.5), Vector2(-398.3, 1333.2), Vector2(-371.5, 1308.8), Vector2(-338.5, 1297.8), Vector2(-314.9, 1280.1), Vector2(-324.3, 1255.8), Vector2(-338.5, 1280.1), Vector2(-381.0, 1273.5),
		Vector2(-392.0, 1244.7), Vector2(-382.6, 1222.6), Vector2(-404.6, 1209.3), Vector2(-440.8, 1216.0), Vector2(-472.3, 1244.7), Vector2(-464.4, 1227.0), Vector2(-432.9, 1204.9), Vector2(-415.6, 1185.0),
		Vector2(-377.8, 1183.9), Vector2(-330.6, 1185.0), Vector2(-283.4, 1162.9), Vector2(-259.8, 1154.0), Vector2(-248.7, 1134.1), Vector2(-251.9, 1107.6), Vector2(-275.5, 1087.7), Vector2(-307.0, 1072.2),
		Vector2(-338.5, 1045.7), Vector2(-354.2, 1012.5), Vector2(-384.1, 961.6), Vector2(-409.3, 990.4), Vector2(-434.5, 1003.7), Vector2(-461.3, 988.2), Vector2(-466.0, 948.4), Vector2(-495.9, 941.7),
		Vector2(-527.4, 924.0), Vector2(-590.4, 913.0), Vector2(-598.2, 957.2), Vector2(-582.5, 1012.5), Vector2(-577.8, 1056.7), Vector2(-593.5, 1078.9), Vector2(-612.4, 1112.0), Vector2(-618.7, 1145.2),
		Vector2(-628.1, 1160.7), Vector2(-645.5, 1134.1), Vector2(-665.9, 1123.1), Vector2(-664.4, 1078.9), Vector2(-708.4, 1072.2), Vector2(-747.8, 1058.9), Vector2(-795.0, 1032.4), Vector2(-826.5, 1030.2),
		Vector2(-853.3, 997.0), Vector2(-862.7, 968.3), Vector2(-850.1, 935.1), Vector2(-826.5, 906.4), Vector2(-799.7, 888.7), Vector2(-739.9, 868.8), Vector2(-732.1, 824.5), Vector2(-787.2, 780.3),
		Vector2(-865.9, 791.4), Vector2(-944.6, 795.8), Vector2(-1070.5, 791.4), Vector2(-1180.7, 802.4), Vector2(-1338.2, 769.2), Vector2(-1495.6, 758.2),
	],
	[  # Baffin Island
		Vector2(-401.4, 926.3), Vector2(-381.0, 895.3), Vector2(-393.6, 862.1), Vector2(-354.2, 824.5), Vector2(-343.2, 809.1), Vector2(-377.8, 791.4), Vector2(-425.1, 758.2), Vector2(-464.4, 733.9),
		Vector2(-503.8, 691.8), Vector2(-629.7, 691.8), Vector2(-661.2, 747.1), Vector2(-629.7, 778.1), Vector2(-535.3, 804.6), Vector2(-511.6, 826.7), Vector2(-495.9, 879.8), Vector2(-440.8, 901.9),
	],
	[  # Greenland
		Vector2(-55.1, 972.7), Vector2(-86.6, 955.0), Vector2(-125.9, 946.2), Vector2(-165.3, 901.9), Vector2(-184.2, 875.4), Vector2(-201.5, 844.4), Vector2(-215.7, 815.7), Vector2(-204.7, 780.3),
		Vector2(-176.3, 764.8), Vector2(-228.3, 740.5), Vector2(-236.1, 714.0), Vector2(-259.8, 689.6), Vector2(-314.9, 614.4), Vector2(314.9, 614.4), Vector2(291.2, 702.9), Vector2(283.4, 736.1),
		Vector2(244.0, 758.2), Vector2(196.8, 780.3), Vector2(125.9, 786.9), Vector2(70.8, 835.6), Vector2(23.6, 846.6), Vector2(-7.9, 879.8), Vector2(-23.6, 906.4), Vector2(-39.4, 946.2),
	],
	[  # Iceland
		Vector2(272.0, 884.2), Vector2(270.0, 878.7), Vector2(277.9, 877.6), Vector2(284.2, 876.5), Vector2(287.3, 872.1), Vector2(278.7, 867.7), Vector2(267.6, 863.9), Vector2(250.3, 861.0),
		Vector2(262.9, 857.7), Vector2(278.7, 855.5), Vector2(245.6, 846.6), Vector2(259.8, 831.2), Vector2(277.1, 826.7), Vector2(299.1, 833.4), Vector2(322.7, 833.4), Vector2(346.3, 831.2),
		Vector2(377.8, 824.5), Vector2(399.9, 829.0), Vector2(401.4, 846.6), Vector2(415.6, 855.5), Vector2(401.4, 871.0), Vector2(385.7, 875.4), Vector2(365.2, 884.2), Vector2(338.5, 893.1),
		Vector2(311.7, 890.9), Vector2(292.8, 883.8),
	],
	[  # Newfoundland
		Vector2(-199.1, 1243.6), Vector2(-207.8, 1263.5), Vector2(-220.4, 1259.1), Vector2(-244.0, 1253.6), Vector2(-255.0, 1242.5), Vector2(-303.8, 1242.5), Vector2(-299.1, 1222.6), Vector2(-283.4, 1200.5),
		Vector2(-270.8, 1171.7), Vector2(-245.6, 1154.0), Vector2(-245.6, 1189.4), Vector2(-220.4, 1200.5), Vector2(-212.5, 1218.2), Vector2(-204.7, 1233.7),
	],
	[  # Cuba
		Vector2(-707.6, 1810.9), Vector2(-684.8, 1788.7), Vector2(-667.5, 1783.2), Vector2(-645.5, 1784.3), Vector2(-629.7, 1787.6), Vector2(-598.2, 1802.0), Vector2(-582.5, 1817.5), Vector2(-560.5, 1828.5),
		Vector2(-537.6, 1848.4), Vector2(-544.7, 1855.1), Vector2(-563.6, 1854.0), Vector2(-593.5, 1856.2), Vector2(-587.2, 1837.4), Vector2(-614.0, 1817.5), Vector2(-636.0, 1813.1), Vector2(-653.3, 1806.4),
		Vector2(-669.1, 1802.0), Vector2(-684.8, 1810.9), Vector2(-699.0, 1814.2),
	],
	[  # Great Britain
		Vector2(540.0, 1188.3), Vector2(551.0, 1189.4), Vector2(563.6, 1181.7), Vector2(573.0, 1183.9), Vector2(576.2, 1176.2), Vector2(591.2, 1176.2), Vector2(604.5, 1173.9), Vector2(614.0, 1172.8),
		Vector2(633.7, 1172.8), Vector2(645.5, 1168.4), Vector2(651.8, 1164.0), Vector2(652.5, 1158.5), Vector2(643.9, 1155.1), Vector2(650.2, 1149.6), Vector2(657.3, 1135.2), Vector2(655.7, 1124.2),
		Vector2(643.9, 1123.7), Vector2(635.2, 1126.4), Vector2(635.2, 1120.9), Vector2(634.4, 1112.0), Vector2(628.9, 1108.7), Vector2(626.6, 1098.8), Vector2(620.3, 1089.9), Vector2(610.8, 1085.5),
		Vector2(606.9, 1077.7), Vector2(604.5, 1065.6), Vector2(597.4, 1060.1), Vector2(590.4, 1055.6), Vector2(588.8, 1050.1), Vector2(590.4, 1043.5), Vector2(596.7, 1031.3), Vector2(601.4, 1023.6),
		Vector2(590.4, 1019.1), Vector2(573.0, 1020.2), Vector2(565.2, 1021.4), Vector2(569.9, 1015.8), Vector2(581.7, 999.2), Vector2(576.2, 998.1), Vector2(551.0, 999.2), Vector2(546.3, 1007.0),
		Vector2(540.0, 1015.8), Vector2(540.8, 1028.0), Vector2(538.4, 1039.0), Vector2(541.6, 1045.7), Vector2(543.1, 1056.7), Vector2(540.0, 1071.1), Vector2(551.0, 1067.8), Vector2(552.6, 1060.1),
		Vector2(557.3, 1070.0), Vector2(550.2, 1078.9), Vector2(551.0, 1086.6), Vector2(560.5, 1084.4), Vector2(573.0, 1080.0), Vector2(576.2, 1089.9), Vector2(582.5, 1098.8), Vector2(581.7, 1106.5),
		Vector2(582.5, 1114.2), Vector2(573.0, 1116.4), Vector2(557.3, 1114.2), Vector2(557.3, 1126.4), Vector2(565.2, 1131.9), Vector2(563.6, 1139.7), Vector2(555.7, 1144.1), Vector2(546.3, 1148.5),
		Vector2(551.0, 1154.0), Vector2(563.6, 1155.1), Vector2(579.3, 1158.5), Vector2(587.2, 1155.1), Vector2(582.5, 1162.9), Vector2(573.0, 1162.9), Vector2(563.6, 1162.9), Vector2(557.3, 1168.4),
		Vector2(551.0, 1177.3),
	],
	[  # Ireland
		Vector2(475.4, 1157.4), Vector2(495.9, 1154.0), Vector2(511.6, 1146.3), Vector2(529.0, 1141.4), Vector2(535.3, 1124.2), Vector2(534.5, 1115.8), Vector2(532.1, 1103.2), Vector2(543.9, 1095.4),
		Vector2(543.1, 1087.7), Vector2(538.4, 1078.9), Vector2(531.3, 1074.4), Vector2(513.2, 1070.4), Vector2(503.8, 1074.4), Vector2(494.3, 1080.0), Vector2(499.1, 1088.8), Vector2(484.9, 1094.3),
		Vector2(470.7, 1095.4), Vector2(473.9, 1109.8), Vector2(469.1, 1114.2), Vector2(488.0, 1118.7), Vector2(480.2, 1129.7), Vector2(466.0, 1141.9), Vector2(469.1, 1149.6),
	],
	[  # Europe
		Vector2(541.6, 1499.0), Vector2(530.5, 1488.0), Vector2(513.2, 1472.5), Vector2(503.8, 1476.9), Vector2(488.8, 1476.9), Vector2(491.2, 1454.8), Vector2(480.2, 1438.2), Vector2(488.0, 1419.4),
		Vector2(492.8, 1384.0), Vector2(489.6, 1364.1), Vector2(483.3, 1346.4), Vector2(497.5, 1335.4), Vector2(508.5, 1327.6), Vector2(538.4, 1331.0), Vector2(569.9, 1334.3), Vector2(601.4, 1335.4),
		Vector2(606.1, 1331.0), Vector2(610.0, 1308.8), Vector2(610.8, 1284.5), Vector2(607.7, 1273.5), Vector2(596.7, 1260.2), Vector2(590.4, 1249.1), Vector2(579.3, 1244.7), Vector2(560.5, 1238.1),
		Vector2(554.9, 1225.9), Vector2(563.6, 1219.3), Vector2(582.5, 1216.0), Vector2(598.2, 1219.3), Vector2(604.5, 1217.1), Vector2(600.6, 1196.1), Vector2(610.8, 1202.7), Vector2(626.6, 1204.9),
		Vector2(631.3, 1200.9), Vector2(639.2, 1192.7), Vector2(654.9, 1183.9), Vector2(654.9, 1172.8), Vector2(658.8, 1168.4), Vector2(669.9, 1165.5), Vector2(680.9, 1159.6), Vector2(688.0, 1157.4),
		Vector2(693.5, 1146.3), Vector2(700.6, 1137.5), Vector2(703.7, 1124.2), Vector2(724.2, 1113.1), Vector2(743.1, 1110.9), Vector2(755.7, 1109.8), Vector2(766.7, 1103.2), Vector2(769.0, 1092.1),
		Vector2(760.4, 1078.9), Vector2(758.0, 1065.6), Vector2(757.2, 1045.7), Vector2(765.1, 1032.4), Vector2(796.6, 1018.0), Vector2(795.0, 1030.2), Vector2(791.9, 1045.7), Vector2(801.3, 1047.9),
		Vector2(782.4, 1067.8), Vector2(785.6, 1082.2), Vector2(801.3, 1092.1), Vector2(802.9, 1101.0), Vector2(820.2, 1097.6), Vector2(840.7, 1087.7), Vector2(853.3, 1102.1), Vector2(875.3, 1096.5),
		Vector2(895.8, 1087.7), Vector2(922.5, 1083.3), Vector2(923.3, 1092.1), Vector2(938.3, 1091.0), Vector2(952.5, 1080.0), Vector2(961.9, 1063.4), Vector2(960.3, 1045.7), Vector2(969.8, 1025.8),
		Vector2(985.5, 1018.0), Vector2(1009.1, 1034.6), Vector2(1013.9, 1003.7), Vector2(998.1, 994.8), Vector2(998.1, 983.8), Vector2(1018.6, 980.4), Vector2(1070.5, 979.3), Vector2(1106.7, 969.4),
		Vector2(1086.3, 963.9), Vector2(1053.2, 959.4), Vector2(1023.3, 965.0), Vector2(990.2, 971.6), Vector2(966.6, 955.0), Vector2(965.0, 935.1), Vector2(969.8, 901.9), Vector2(999.7, 879.8),
		Vector2(1028.0, 857.7), Vector2(1010.7, 840.0), Vector2(977.6, 844.4), Vector2(960.3, 866.5), Vector2(932.0, 888.7), Vector2(906.8, 915.2), Vector2(902.1, 946.2), Vector2(903.6, 955.0),
		Vector2(922.5, 965.0), Vector2(927.3, 977.1), Vector2(914.7, 983.8), Vector2(894.2, 997.0), Vector2(891.1, 1014.7), Vector2(887.9, 1042.4), Vector2(875.3, 1052.3), Vector2(854.8, 1067.8),
		Vector2(832.8, 1071.1), Vector2(829.7, 1055.6), Vector2(826.5, 1043.5), Vector2(817.1, 1019.1), Vector2(806.0, 1003.7), Vector2(804.5, 990.4), Vector2(798.2, 970.5), Vector2(790.3, 990.4),
		Vector2(780.9, 990.4), Vector2(755.7, 1009.2), Vector2(733.6, 1011.4), Vector2(717.9, 992.6), Vector2(708.4, 977.1), Vector2(708.4, 959.4), Vector2(705.3, 941.7), Vector2(710.0, 924.0),
		Vector2(727.3, 910.8), Vector2(750.9, 899.7), Vector2(771.4, 886.5), Vector2(795.0, 871.0), Vector2(809.2, 857.7), Vector2(826.5, 835.6), Vector2(840.7, 813.5), Vector2(856.4, 806.8),
		Vector2(872.2, 784.7), Vector2(889.5, 769.2), Vector2(927.3, 754.9), Vector2(960.3, 744.9), Vector2(1002.8, 731.6), Vector2(1035.9, 721.7), Vector2(1070.5, 725.0), Vector2(1117.8, 740.5),
		Vector2(1259.4, 791.4), Vector2(1259.4, 1366.3), Vector2(1086.3, 1388.5), Vector2(1046.9, 1406.2), Vector2(1007.6, 1392.9), Vector2(991.8, 1397.3), Vector2(985.5, 1410.6), Vector2(991.8, 1426.1),
		Vector2(990.2, 1441.5), Vector2(1001.3, 1454.8), Vector2(993.4, 1468.1), Vector2(983.9, 1489.1), Vector2(977.6, 1476.9), Vector2(971.3, 1481.3), Vector2(961.9, 1459.2), Vector2(966.6, 1448.2),
		Vector2(958.8, 1434.9), Vector2(947.7, 1421.6), Vector2(935.1, 1401.7), Vector2(936.7, 1381.8), Vector2(932.0, 1368.6), Vector2(921.0, 1356.4), Vector2(897.4, 1344.2), Vector2(880.0, 1331.0),
		Vector2(869.0, 1317.7), Vector2(858.0, 1295.6), Vector2(843.8, 1302.2), Vector2(846.2, 1285.6), Vector2(823.4, 1291.2), Vector2(823.4, 1308.8), Vector2(828.1, 1321.0), Vector2(843.8, 1333.2),
		Vector2(853.3, 1356.4), Vector2(865.9, 1366.3), Vector2(884.0, 1368.6), Vector2(895.8, 1386.2), Vector2(913.1, 1397.3), Vector2(921.0, 1408.4), Vector2(918.6, 1415.0), Vector2(902.1, 1400.6),
		Vector2(891.1, 1410.6), Vector2(889.5, 1423.8), Vector2(899.7, 1432.7), Vector2(889.5, 1446.0), Vector2(876.1, 1455.9), Vector2(876.9, 1449.3), Vector2(881.6, 1439.3), Vector2(880.0, 1421.6),
		Vector2(875.3, 1409.5), Vector2(864.3, 1403.9), Vector2(854.1, 1392.9), Vector2(846.2, 1382.9), Vector2(832.0, 1379.6), Vector2(821.8, 1372.5), Vector2(815.5, 1364.1), Vector2(805.3, 1356.4),
		Vector2(795.0, 1345.3), Vector2(791.9, 1332.1), Vector2(788.7, 1321.0), Vector2(769.8, 1313.3), Vector2(757.2, 1324.3), Vector2(747.8, 1327.6), Vector2(739.9, 1332.1), Vector2(727.3, 1342.0),
		Vector2(713.9, 1337.6), Vector2(702.1, 1335.4), Vector2(686.4, 1337.6), Vector2(677.7, 1354.2), Vector2(680.9, 1367.5), Vector2(664.4, 1380.7), Vector2(647.0, 1387.4), Vector2(643.1, 1395.1),
		Vector2(625.0, 1422.7), Vector2(632.9, 1438.2), Vector2(621.8, 1448.2), Vector2(617.9, 1463.6), Vector2(604.5, 1471.4), Vector2(595.1, 1483.6), Vector2(574.6, 1483.6), Vector2(560.5, 1483.6),
		Vector2(545.5, 1495.7),
	],
	[  # Africa
		Vector2(536.8, 1503.5), Vector2(532.1, 1518.9), Vector2(522.7, 1543.3), Vector2(510.1, 1552.1), Vector2(495.9, 1561.0), Vector2(484.1, 1580.9), Vector2(475.4, 1600.8), Vector2(478.6, 1622.9),
		Vector2(469.1, 1645.0), Vector2(448.7, 1671.5), Vector2(425.1, 1684.8), Vector2(401.4, 1718.0), Vector2(379.4, 1768.8), Vector2(363.7, 1824.1), Vector2(370.0, 1875.0), Vector2(362.1, 1970.1),
		Vector2(393.6, 2074.0), Vector2(1259.4, 2074.0), Vector2(1138.2, 1603.0), Vector2(1102.0, 1600.8), Vector2(1023.3, 1596.3), Vector2(991.8, 1576.4), Vector2(968.2, 1567.6), Vector2(944.6, 1585.3),
		Vector2(936.7, 1620.7), Vector2(913.1, 1614.0), Vector2(889.5, 1605.2), Vector2(869.0, 1580.9), Vector2(837.5, 1567.6), Vector2(810.8, 1561.0), Vector2(799.7, 1547.7), Vector2(788.7, 1538.8),
		Vector2(799.7, 1525.6), Vector2(804.5, 1510.1), Vector2(796.6, 1501.2), Vector2(803.7, 1480.2), Vector2(791.9, 1480.2), Vector2(784.0, 1469.2), Vector2(765.1, 1478.0), Vector2(752.5, 1479.1),
		Vector2(732.1, 1474.7), Vector2(710.0, 1481.3), Vector2(678.5, 1481.3), Vector2(650.2, 1488.0), Vector2(619.5, 1504.6), Vector2(599.8, 1517.8), Vector2(582.5, 1514.5), Vector2(560.5, 1515.6),
		Vector2(546.3, 1501.2),
	],
]
const ISLANDS := [
	[Vector2(676.2, 1419.4), Vector2(10.0, 7.5)],
	[Vector2(772.2, 1363.0), Vector2(8.3, 18.3)],
	[Vector2(771.4, 1409.5), Vector2(12.0, 27.0)],
	[Vector2(851.7, 1464.8), Vector2(28.0, 19.0)],
	[Vector2(368.4, 1669.3), Vector2(6.0, 5.0)],
	[Vector2(384.9, 1677.1), Vector2(5.0, 5.0)],
	[Vector2(409.3, 1667.1), Vector2(5.0, 10.0)],
	[Vector2(229.1, 1459.7), Vector2(13.0, 3.2)],
	[Vector2(201.5, 1439.3), Vector2(3.5, 2.5)],
	[Vector2(182.6, 1443.7), Vector2(5.0, 2.5)],
	[Vector2(362.9, 1571.6), Vector2(11.0, 4.6)],
	[Vector2(-389.6, 1580.4), Vector2(7.5, 3.2)],
	[Vector2(521.1, 922.9), Vector2(7.5, 11.0)],
	[Vector2(610.0, 961.6), Vector2(3.0, 14.0)],
	[Vector2(582.5, 990.4), Vector2(5.0, 4.0)],
	[Vector2(519.5, 1016.9), Vector2(3.0, 20.0)],
	[Vector2(558.9, 1096.5), Vector2(2.5, 3.3)],
	[Vector2(815.5, 1067.8), Vector2(12.0, 10.0)],
	[Vector2(791.9, 1072.2), Vector2(6.0, 6.0)],
	[Vector2(921.0, 1023.6), Vector2(5.0, 13.0)],
	[Vector2(864.3, 1076.6), Vector2(3.0, 2.5)],
	[Vector2(-366.8, 1269.0), Vector2(22.0, 3.0)],
	[Vector2(-360.5, 1201.6), Vector2(22.0, 5.5)],
	[Vector2(-606.1, 1706.9), Vector2(9.6, 1.8)],
	[Vector2(-596.7, 1755.6), Vector2(6.0, 15.0)],
	[Vector2(-588.8, 1741.2), Vector2(2.2, 1.2)],
	[Vector2(-481.7, 1379.6), Vector2(2.5, 1.0)],
	[Vector2(-473.1, 1382.3), Vector2(2.5, 1.0)],
	[Vector2(536.1, 1029.1), Vector2(3.0, 5.0)],
	[Vector2(532.1, 1047.9), Vector2(3.0, 3.0)],
	[Vector2(595.9, 1206.9), Vector2(1.8, 1.2)],
]
const RISES := [
	[Vector2(-960.3, 1410.6), Vector2(90.0, 140.0), 950.0],
	[Vector2(-724.2, 1388.5), Vector2(90.0, 60.0), 190.0],
	[Vector2(-503.8, 1156.3), Vector2(110.0, 70.0), 450.0],
	[Vector2(-362.1, 1101.0), Vector2(50.0, 40.0), 500.0],
	[Vector2(-976.1, 1764.4), Vector2(70.0, 80.0), 1600.0],
	[Vector2(-1204.3, 1421.6), Vector2(50.0, 60.0), 1300.0],
	[Vector2(-1109.9, 1476.9), Vector2(50.0, 40.0), 1500.0],
	[Vector2(-826.5, 1488.0), Vector2(25.0, 18.0), 350.0],
	[Vector2(-928.8, 1620.7), Vector2(35.0, 25.0), 400.0],
	[Vector2(569.9, 1406.2), Vector2(55.0, 50.0), 640.0],
	[Vector2(677.0, 1293.4), Vector2(20.0, 18.0), 900.0],
	[Vector2(669.1, 1216.0), Vector2(40.0, 30.0), 95.0],
	[Vector2(558.9, 1030.2), Vector2(25.0, 20.0), 750.0],
	[Vector2(571.5, 1136.4), Vector2(12.0, 15.0), 450.0],
	[Vector2(595.1, 1094.3), Vector2(8.0, 25.0), 420.0],
	[Vector2(338.5, 859.9), Vector2(35.0, 15.0), 1100.0],
	[Vector2(-31.5, 802.4), Vector2(65.0, 120.0), 2600.0],
	[Vector2(873.7, 901.9), Vector2(40.0, 60.0), 450.0],
	[Vector2(1039.0, 901.9), Vector2(35.0, 45.0), 150.0],
	[Vector2(787.2, 1178.4), Vector2(40.0, 25.0), 420.0],
	[Vector2(858.0, 1193.8), Vector2(25.0, 20.0), 450.0],
	[Vector2(936.7, 1344.2), Vector2(30.0, 30.0), 1100.0],
	[Vector2(708.4, 1676.0), Vector2(150.0, 80.0), 400.0],
	[Vector2(-637.6, 1421.6), Vector2(35.0, 30.0), 350.0],
	[Vector2(-440.8, 791.4), Vector2(40.0, 30.0), 1200.0],
	[Vector2(772.2, 1363.0), Vector2(6.0, 12.0), 1500.0],
	[Vector2(771.4, 1410.6), Vector2(8.0, 18.0), 850.0],
	[Vector2(865.9, 1460.3), Vector2(6.0, 6.0), 2600.0],
	[Vector2(248.7, 842.2), Vector2(8.0, 6.0), 500.0],
	[Vector2(368.4, 1669.3), Vector2(4.0, 4.0), 2400.0],
	[Vector2(362.9, 1570.9), Vector2(7.0, 3.0), 1300.0],
	[Vector2(229.8, 1459.2), Vector2(8.0, 2.0), 700.0],
	[Vector2(521.1, 922.9), Vector2(5.0, 8.0), 600.0],
	[Vector2(-834.4, 1244.7), Vector2(60.0, 40.0), 300.0],
	[Vector2(-621.8, 1308.8), Vector2(40.0, 25.0), 260.0],
]
const RANGES := [
	[Vector2(-1039.0, 1565.4), Vector2(-1046.9, 1421.6), 45.0, 2600.0],
	[Vector2(-1046.9, 1421.6), Vector2(-1109.9, 1311.1), 45.0, 2600.0],
	[Vector2(-1109.9, 1311.1), Vector2(-1188.6, 1200.5), 45.0, 2400.0],
	[Vector2(-1188.6, 1200.5), Vector2(-1259.4, 1089.9), 40.0, 2400.0],
	[Vector2(-1259.4, 1089.9), Vector2(-1369.6, 968.3), 40.0, 2000.0],
	[Vector2(-1228.0, 1514.5), Vector2(-1279.9, 1403.9), 18.0, 2800.0],
	[Vector2(-1279.9, 1403.9), Vector2(-1283.1, 1211.5), 18.0, 2200.0],
	[Vector2(-1267.3, 1512.3), Vector2(-1314.5, 1410.6), 8.0, 800.0],
	[Vector2(-1250.0, 1526.7), Vector2(-1205.9, 1533.3), 7.0, 1200.0],
	[Vector2(-700.6, 1532.2), Vector2(-621.8, 1454.8), 22.0, 1100.0],
	[Vector2(-621.8, 1454.8), Vector2(-563.6, 1379.6), 16.0, 650.0],
	[Vector2(-538.4, 1359.7), Vector2(-495.9, 1308.8), 16.0, 1000.0],
	[Vector2(-551.0, 1271.3), Vector2(-481.7, 1242.5), 22.0, 700.0],
	[Vector2(-377.8, 1012.5), Vector2(-362.1, 968.3), 15.0, 1300.0],
	[Vector2(-1007.6, 1830.8), Vector2(-1078.4, 1631.7), 35.0, 2200.0],
	[Vector2(-936.7, 1830.8), Vector2(-968.2, 1720.2), 25.0, 2000.0],
	[Vector2(736.8, 1322.1), Vector2(752.5, 1277.9), 22.0, 3000.0],
	[Vector2(752.5, 1277.9), Vector2(795.0, 1264.6), 22.0, 3100.0],
	[Vector2(795.0, 1264.6), Vector2(842.3, 1251.3), 22.0, 2800.0],
	[Vector2(842.3, 1251.3), Vector2(881.6, 1242.5), 15.0, 1500.0],
	[Vector2(601.4, 1344.2), Vector2(675.4, 1355.3), 12.0, 2400.0],
	[Vector2(511.6, 1344.2), Vector2(574.6, 1342.0), 10.0, 1700.0],
	[Vector2(566.7, 1476.9), Vector2(590.4, 1474.7), 8.0, 2300.0],
	[Vector2(763.5, 1313.3), Vector2(810.8, 1326.5), 9.0, 1500.0],
	[Vector2(810.8, 1326.5), Vector2(856.4, 1364.1), 8.0, 1900.0],
	[Vector2(856.4, 1364.1), Vector2(884.8, 1432.7), 9.0, 1600.0],
	[Vector2(858.0, 1288.9), Vector2(936.7, 1366.3), 15.0, 1700.0],
	[Vector2(732.1, 990.4), Vector2(779.3, 913.0), 30.0, 1800.0],
	[Vector2(779.3, 913.0), Vector2(858.0, 824.5), 25.0, 1500.0],
	[Vector2(858.0, 824.5), Vector2(944.6, 769.2), 22.0, 1400.0],
	[Vector2(480.2, 1614.0), Vector2(558.9, 1576.4), 22.0, 3000.0],
	[Vector2(558.9, 1576.4), Vector2(677.0, 1521.1), 18.0, 2000.0],
	[Vector2(677.0, 1521.1), Vector2(771.4, 1503.5), 15.0, 1500.0],
]
const LAKES := [
	{"x": -749368.0, "z": 1241395.8, "rx": 54000.0, "rz": 22000.0, "level": 183.0, "name": "Lake Superior"},
	{"x": -739922.2, "z": 1322114.8, "rx": 17000.0, "rz": 47000.0, "level": 176.0, "name": "Lake Michigan"},
	{"x": -667504.3, "z": 1303317.2, "rx": 27000.0, "rz": 22000.0, "level": 176.0, "name": "Lake Huron"},
	{"x": -648612.6, "z": 1363027.2, "rx": 37000.0, "rz": 8000.0, "level": 174.0, "name": "Lake Erie"},
	{"x": -593512.1, "z": 1332066.5, "rx": 27000.0, "rz": 6500.0, "level": 75.0, "name": "Lake Ontario"},
	{"x": -642787.7, "z": 1699172.1, "rx": 5000.0, "rz": 5000.0, "level": 4.0, "name": "Lake Okeechobee"},
	{"x": -1141369.3, "z": 1386247.7, "rx": 7000.0, "rz": 9000.0, "level": 1280.0, "name": "Great Salt Lake"},
	{"x": -905224.0, "z": 1140773.4, "rx": 9000.0, "rz": 38000.0, "level": 217.0, "name": "Lake Winnipeg"},
	{"x": 732837.8, "z": 1267933.5, "rx": 7000.0, "rz": 1600.0, "level": 372.0, "name": "Lake Geneva"},
	{"x": 837529.0, "z": 992604.3, "rx": 13000.0, "rz": 7000.0, "level": 44.0, "name": "Lake Vänern"},
	{"x": 857994.9, "z": 1005873.2, "rx": 2600.0, "rz": 12000.0, "level": 88.0, "name": "Lake Vättern"},
	{"x": 715520.5, "z": 1125293.1, "rx": 6000.0, "rz": 6000.0, "level": 0.0, "name": "IJsselmeer"},
	{"x": -524242.7, "z": 1311057.4, "rx": 1800.0, "rz": 12000.0, "level": 30.0, "name": "Lake Champlain"},
	{"x": 908372.6, "z": 1259087.6, "rx": 7000.0, "rz": 1200.0, "level": 104.0, "name": "Lake Balaton"},
	{"x": -540200.0, "z": 1395720.0, "rx": 3300.0, "rz": 3200.0, "level": -1.0, "name": "Upper New York Bay"},
	{"x": -540800.0, "z": 1400720.0, "rx": 6000.0, "rz": 4500.0, "level": -1.0, "name": "Lower Bay"},
	{"x": -493190.0, "z": 1358580.0, "rx": 3200.0, "rz": 2600.0, "level": -1.0, "name": "Boston Harbor"},
	{"x": -1289410.0, "z": 1455710.0, "rx": 4000.0, "rz": 9000.0, "level": -1.0, "name": "San Francisco Bay"},
]
const RIVERS := [
	{"name": "Mississippi", "w": 900.0, "pts": [Vector2(-869.0, 1251.3), Vector2(-837.5, 1300.0), Vector2(-806.0, 1344.2), Vector2(-796.6, 1377.4), Vector2(-804.5, 1410.6), Vector2(-790.3, 1441.5), Vector2(-776.1, 1476.9), Vector2(-787.2, 1518.9), Vector2(-804.5, 1565.4), Vector2(-809.2, 1598.5), Vector2(-806.0, 1622.9), Vector2(-788.7, 1632.8), Vector2(-777.7, 1648.3)]},
	{"name": "St. Lawrence", "w": 1600.0, "pts": [Vector2(-573.0, 1318.8), Vector2(-551.0, 1302.2), Vector2(-528.2, 1288.9), Vector2(-511.6, 1271.3), Vector2(-491.2, 1260.2), Vector2(-475.4, 1248.0)]},
	{"name": "Rhine", "w": 500.0, "pts": [Vector2(749.4, 1243.6), Vector2(749.4, 1220.4), Vector2(762.0, 1200.5), Vector2(759.6, 1189.4), Vector2(749.4, 1181.7), Vector2(739.1, 1168.4), Vector2(734.4, 1157.4), Vector2(722.6, 1148.5), Vector2(702.1, 1147.0), Vector2(695.1, 1146.3)]},
	{"name": "Danube", "w": 600.0, "pts": [Vector2(763.5, 1233.7), Vector2(818.6, 1211.5), Vector2(854.8, 1227.0), Vector2(887.9, 1229.2), Vector2(898.9, 1230.3), Vector2(927.3, 1238.1), Vector2(929.6, 1244.7), Vector2(927.3, 1277.9), Vector2(949.3, 1295.6), Vector2(983.9, 1313.3)]},
	{"name": "Loire", "w": 300.0, "pts": [Vector2(692.7, 1288.9), Vector2(675.4, 1251.3), Vector2(659.6, 1235.9), Vector2(640.7, 1246.9), Vector2(621.1, 1245.8), Vector2(605.3, 1251.3), Vector2(593.5, 1249.8)]},
	{"name": "Tagus", "w": 300.0, "pts": [Vector2(590.4, 1401.7), Vector2(566.7, 1413.9), Vector2(535.3, 1418.3), Vector2(511.6, 1423.8), Vector2(489.6, 1437.1), Vector2(483.3, 1439.8)]},
	{"name": "Po", "w": 260.0, "pts": [Vector2(750.9, 1298.9), Vector2(774.6, 1296.7), Vector2(799.7, 1298.9), Vector2(818.6, 1301.1), Vector2(826.5, 1301.1)]},
	{"name": "Rhône", "w": 300.0, "pts": [Vector2(705.3, 1283.4), Vector2(705.3, 1322.1), Vector2(702.9, 1336.5)]},
	{"name": "Columbia", "w": 700.0, "pts": [Vector2(-1242.1, 1273.5), Vector2(-1275.2, 1285.6), Vector2(-1305.1, 1280.1), Vector2(-1321.6, 1272.4)]},
	{"name": "Colorado", "w": 160.0, "pts": [Vector2(-1086.3, 1441.5), Vector2(-1127.2, 1496.8), Vector2(-1165.0, 1499.0), Vector2(-1174.4, 1521.1), Vector2(-1174.4, 1552.1), Vector2(-1178.4, 1593.0)]},
	{"name": "Elbe", "w": 350.0, "pts": [Vector2(856.4, 1178.4), Vector2(824.9, 1154.0), Vector2(812.3, 1131.9), Vector2(787.2, 1110.9), Vector2(768.3, 1103.2)]},
	{"name": "Hudson River", "w": 1150.0, "pts": [Vector2(-540.1, 1329.2), Vector2(-539.9, 1359.2), Vector2(-540.0, 1380.2), Vector2(-540.1, 1386.2), Vector2(-540.2, 1390.7), Vector2(-540.4, 1393.2)]},
	{"name": "East River", "w": 650.0, "pts": [Vector2(-535.9, 1382.7), Vector2(-536.3, 1386.2), Vector2(-537.0, 1389.7), Vector2(-538.7, 1393.4)]},
	{"name": "Potomac", "w": 520.0, "pts": [Vector2(-594.7, 1421.0), Vector2(-581.7, 1430.0), Vector2(-576.2, 1433.5), Vector2(-574.9, 1436.2), Vector2(-575.3, 1440.0), Vector2(-574.2, 1447.0)]},
	{"name": "Golden Gate", "w": 1800.0, "pts": [Vector2(-1291.4, 1449.7), Vector2(-1297.9, 1448.9), Vector2(-1305.4, 1448.8), Vector2(-1311.4, 1448.7)], "sea": true},
	{"name": "Thames", "w": 320.0, "pts": [Vector2(601.1, 1158.4), Vector2(614.1, 1158.5), Vector2(626.1, 1157.5), Vector2(631.1, 1157.8), Vector2(633.6, 1157.2), Vector2(635.1, 1156.7), Vector2(636.9, 1157.4), Vector2(638.1, 1158.3), Vector2(639.7, 1157.2), Vector2(643.1, 1156.8), Vector2(649.1, 1156.3), Vector2(657.1, 1155.9), Vector2(665.1, 1155.3)]},
	{"name": "Seine", "w": 240.0, "pts": [Vector2(677.9, 1231.3), Vector2(669.9, 1226.3), Vector2(666.4, 1223.9), Vector2(663.9, 1222.6), Vector2(661.3, 1223.6), Vector2(659.7, 1222.9), Vector2(658.7, 1220.1), Vector2(654.9, 1218.8), Vector2(648.9, 1215.8), Vector2(639.9, 1213.3)]},
	{"name": "Tiber", "w": 160.0, "pts": [Vector2(837.6, 1345.3), Vector2(835.9, 1354.3), Vector2(833.9, 1358.7), Vector2(833.6, 1361.7), Vector2(834.3, 1363.5), Vector2(830.6, 1366.3), Vector2(826.1, 1368.3)]},
]
## Parks keep the city scatter out: {name, x, z, hw, hd} in metres.
const PARKS := [
	{"name": "Central Park", "x": -538200.0, "z": 1384420.0, "hw": 420.0, "hd": 2000.0},
	{"name": "National Mall", "x": -573130.0, "z": 1435290.0, "hw": 1700.0, "hd": 180.0},
	{"name": "Golden Gate Park", "x": -1298910.0, "z": 1453710.0, "hw": 2400.0, "hd": 350.0},
	{"name": "Hyde Park", "x": 631740.0, "z": 1155720.0, "hw": 900.0, "hd": 550.0},
	{"name": "Regent's Park", "x": 633440.0, "z": 1153320.0, "hw": 600.0, "hd": 500.0},
	{"name": "Champ de Mars", "x": 661070.0, "z": 1224770.0, "hw": 250.0, "hd": 550.0},
	{"name": "Bois de Boulogne", "x": 658470.0, "z": 1221920.0, "hw": 1100.0, "hd": 1400.0},
	{"name": "Villa Borghese", "x": 834870.0, "z": 1359670.0, "hw": 500.0, "hd": 450.0},
]
## Landmarks: kind picks the model in Landmarks; x, z metres; yaw = heading of the model's forward axis.
const LANDMARKS := [
	{"id": "liberty", "name": "Statue of Liberty", "kind": "liberty", "x": -540900.0, "z": 1395620.0, "yaw": 40.0, "icao": "KJFK", "city": "New York"},
	{"id": "esb", "name": "Empire State Building", "kind": "empire", "x": -538450.0, "z": 1387820.0, "yaw": 29.0, "icao": "KJFK", "city": "New York"},
	{"id": "wtc", "name": "One World Trade Center", "kind": "one_wtc", "x": -539200.0, "z": 1391920.0, "yaw": 0.0, "icao": "KJFK", "city": "New York"},
	{"id": "midtown", "name": "Midtown skyline", "kind": "skyline_midtown", "x": -538300.0, "z": 1387420.0, "yaw": 29.0, "icao": "KJFK", "city": "New York"},
	{"id": "downtown", "name": "Lower Manhattan skyline", "kind": "skyline_downtown", "x": -538900.0, "z": 1391520.0, "yaw": 0.0, "icao": "KJFK", "city": "New York"},
	{"id": "bbridge", "name": "Brooklyn Bridge", "kind": "bridge_brooklyn", "x": -537462.4, "z": 1390726.5, "yaw": 294.7, "icao": "KJFK", "city": "New York"},
	{"id": "bosdt", "name": "Downtown Boston", "kind": "skyline_boston", "x": -495890.0, "z": 1357580.0, "yaw": 0.0, "icao": "KBOS", "city": "Boston"},
	{"id": "capitol", "name": "US Capitol", "kind": "capitol", "x": -571230.0, "z": 1435290.0, "yaw": 90.0, "icao": "KIAD", "city": "Washington"},
	{"id": "monument", "name": "Washington Monument", "kind": "obelisk", "x": -573230.0, "z": 1435290.0, "yaw": 0.0, "icao": "KIAD", "city": "Washington"},
	{"id": "willis", "name": "Willis Tower", "kind": "willis", "x": -749790.0, "z": 1369990.0, "yaw": 0.0, "icao": "KORD", "city": "Chicago"},
	{"id": "loop", "name": "The Loop", "kind": "skyline_chicago", "x": -750390.0, "z": 1370090.0, "yaw": 0.0, "icao": "KORD", "city": "Chicago"},
	{"id": "cn", "name": "CN Tower", "kind": "cn_tower", "x": -614700.0, "z": 1327090.0, "yaw": 0.0, "icao": "CYYZ", "city": "Toronto"},
	{"id": "tordt", "name": "Downtown Toronto", "kind": "skyline_toronto", "x": -613400.0, "z": 1326790.0, "yaw": 0.0, "icao": "CYYZ", "city": "Toronto"},
	{"id": "miadt", "name": "Downtown Miami", "kind": "skyline_miami", "x": -630890.0, "z": 1726130.0, "yaw": 0.0, "icao": "KMIA", "city": "Miami"},
	{"id": "hollywood", "name": "Hollywood Sign", "kind": "hollywood", "x": -1223410.0, "z": 1533790.0, "yaw": 0.0, "icao": "KLAX", "city": "Los Angeles"},
	{"id": "ladt", "name": "Downtown Los Angeles", "kind": "skyline_la", "x": -1219710.0, "z": 1539190.0, "yaw": 0.0, "icao": "KLAX", "city": "Los Angeles"},
	{"id": "ggb", "name": "Golden Gate Bridge", "kind": "bridge_golden", "x": -1301210.1, "z": 1448866.0, "yaw": 0.8, "icao": "KSFO", "city": "San Francisco"},
	{"id": "sfdt", "name": "Downtown San Francisco", "kind": "skyline_sf", "x": -1294910.0, "z": 1452210.0, "yaw": 0.0, "icao": "KSFO", "city": "San Francisco"},
	{"id": "bigben", "name": "Big Ben and Parliament", "kind": "big_ben", "x": 633640.0, "z": 1156770.0, "yaw": 0.0, "icao": "EGLL", "city": "London"},
	{"id": "eye", "name": "London Eye", "kind": "london_eye", "x": 634040.0, "z": 1157320.0, "yaw": 0.0, "icao": "EGLL", "city": "London"},
	{"id": "towerbr", "name": "Tower Bridge", "kind": "bridge_tower", "x": 636853.1, "z": 1157386.2, "yaw": 201.3, "icao": "EGLL", "city": "London"},
	{"id": "shard", "name": "The Shard", "kind": "shard", "x": 636240.0, "z": 1157820.0, "yaw": 0.0, "icao": "EGLL", "city": "London"},
	{"id": "city", "name": "The City of London", "kind": "skyline_city", "x": 636040.0, "z": 1156520.0, "yaw": 0.0, "icao": "EGLL", "city": "London"},
	{"id": "wharf", "name": "Canary Wharf", "kind": "skyline_wharf", "x": 639440.0, "z": 1157720.0, "yaw": 0.0, "icao": "EGLL", "city": "London"},
	{"id": "eiffel", "name": "Eiffel Tower", "kind": "eiffel", "x": 660970.0, "z": 1224070.0, "yaw": 35.0, "icao": "LFPG", "city": "Paris"},
	{"id": "arc", "name": "Arc de Triomphe", "kind": "arc", "x": 661570.0, "z": 1221120.0, "yaw": 0.0, "icao": "LFPG", "city": "Paris"},
	{"id": "defense", "name": "La Defense", "kind": "skyline_defense", "x": 657570.0, "z": 1218720.0, "yaw": 0.0, "icao": "LFPG", "city": "Paris"},
	{"id": "mills", "name": "Windmills", "kind": "windmills", "x": 710660.0, "z": 1135340.0, "yaw": 0.0, "icao": "EHAM", "city": "Amsterdam"},
	{"id": "torres", "name": "Cuatro Torres", "kind": "skyline_madrid", "x": 566180.0, "z": 1402180.0, "yaw": 0.0, "icao": "LEMD", "city": "Madrid"},
	{"id": "colosseum", "name": "Colosseum", "kind": "colosseum", "x": 835770.0, "z": 1361770.0, "yaw": 20.0, "icao": "LIRF", "city": "Rome"},
	{"id": "stpeter", "name": "St Peter's Basilica", "kind": "dome_church", "x": 832070.0, "z": 1360970.0, "yaw": 90.0, "icao": "LIRF", "city": "Rome"},
	{"id": "church", "name": "Hallgrimskirkja", "kind": "church_tower", "x": 285110.0, "z": 878240.0, "yaw": 0.0, "icao": "BIKF", "city": "Reykjavik"},
]
const LABELS := [
	["NORTH AMERICA", Vector2(-913.1, 1255.8)],
	["UNITED STATES", Vector2(-865.9, 1454.8)],
	["CANADA", Vector2(-944.6, 1012.5)],
	["GREENLAND", Vector2(-15.7, 747.1)],
	["ICELAND", Vector2(330.6, 853.3)],
	["ATLANTIC OCEAN", Vector2(0.0, 1454.8)],
	["NORTH SEA", Vector2(684.8, 1056.7)],
	["GULF OF MEXICO", Vector2(-787.2, 1735.7)],
	["HUDSON BAY", Vector2(-724.2, 990.4)],
	["MEDITERRANEAN SEA", Vector2(724.2, 1450.4)],
	["EUROPE", Vector2(850.1, 1145.2)],
	["UNITED KINGDOM", Vector2(595.1, 1112.0)],
	["FRANCE", Vector2(669.1, 1260.2)],
	["SPAIN", Vector2(569.9, 1410.6)],
	["ITALY", Vector2(826.5, 1344.2)],
	["IRELAND", Vector2(503.8, 1118.7)],
	["AFRICA", Vector2(629.7, 1676.0)],
	["PACIFIC OCEAN", Vector2(-1338.2, 1565.4)],
	["CARIBBEAN", Vector2(-598.2, 1817.5)],
]


## World metres for a real latitude / longitude.
static func to_world(lat: float, lon: float) -> Vector2:
	return Vector2((lon - LON0) * KX, ORIGIN_Z + (LAT0 - lat) * KZ)


## (lon, lat) of a world position.
static func to_lonlat(x: float, z: float) -> Vector2:
	return Vector2(LON0 + x / KX, LAT0 - (z - ORIGIN_Z) / KZ)


static func contains(x: float, z: float) -> bool:
	return x >= GRID_X0 and x <= GRID_X0 + GRID_NX * CELL and z >= GRID_Z0 and z <= GRID_Z0 + GRID_NZ * CELL


## Name of the sea or ocean at a position in the region.
static func sea_name(x: float, z: float) -> String:
	var ll := to_lonlat(x, z)
	var lon := ll.x
	var lat := ll.y
	if lon < -100.0 and lat < 52.0:
		return "the Pacific Ocean"
	if lat > 18.0 and lat < 30.8 and lon > -98.0 and lon < -81.2:
		return "the Gulf of Mexico"
	if lat > 51.0 and lat < 64.5 and lon > -95.5 and lon < -76.5:
		return "Hudson Bay"
	if lat > 49.0 and lat < 51.2 and lon > -6.0 and lon < 2.0:
		return "the English Channel"
	if lat > 51.2 and lat < 55.6 and lon > -6.4 and lon < -2.8:
		return "the Irish Sea"
	if lat > 51.0 and lat < 61.5 and lon > -4.0 and lon < 10.0:
		return "the North Sea"
	if lat > 53.5 and lat < 66.0 and lon > 9.5:
		return "the Baltic Sea"
	if lat > 43.4 and lat < 48.3 and lon > -10.0 and lon < -1.0:
		return "the Bay of Biscay"
	if lon > -5.6 and lon < 40.0 and lat > 30.0 and lat < 46.0:
		return "the Mediterranean Sea"
	if lat > 58.0 and lon > -66.0 and lon < -45.0:
		return "the Labrador Sea"
	if lat > 63.0 and lon > -45.0 and lon < -13.0:
		return "the Denmark Strait" if lon < -25.0 else "the Norwegian Sea"
	if lat < 24.5 and lon > -86.0 and lon < -74.0:
		return "the Caribbean Sea"
	return "the North Atlantic"


## Air traffic control centre for a position in the region.
static func center_name(x: float, z: float, country: String) -> String:
	var ll := to_lonlat(x, z)
	match country:
		"United States":
			if ll.x < -104.0:
				return "Los Angeles Center" if ll.y < 37.0 else "Oakland Center"
			if ll.x < -84.0:
				return "Chicago Center"
			if ll.y < 30.0:
				return "Miami Center"
			if ll.y < 39.6:
				return "Washington Center"
			return "Boston Center" if ll.x > -72.5 else "New York Center"
		"Canada":
			return "Gander Centre" if ll.x > -60.0 else "Toronto Centre"
		"United Kingdom":
			return "London Control" if ll.y < 54.5 else "Scottish Control"
		"Ireland":
			return "Shannon Control"
		"France":
			return "Paris Control"
		"Netherlands":
			return "Amsterdam Radar"
		"Spain":
			return "Madrid Control"
		"Italy":
			return "Roma Control"
		"Iceland", "Greenland":
			return "Reykjavik Control"
		"Portugal":
			return "Santa Maria Oceanic"
		"Bermuda":
			return "New York Oceanic"
		"Faroe Islands":
			return "Scottish Control"
	return "Shanwick Oceanic" if ll.x > -30.0 else "Gander Oceanic"
