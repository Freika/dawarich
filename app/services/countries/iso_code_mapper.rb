# frozen_string_literal: true

class Countries::IsoCodeMapper
  # Comprehensive country data with name, ISO codes, and flag emoji
  # Based on ISO 3166-1 standard
  COUNTRIES = {
    'AF' => { name: 'Afghanistan', iso2: 'AF', iso3: 'AFG', flag: '🇦🇫' },
    'AL' => { name: 'Albania', iso2: 'AL', iso3: 'ALB', flag: '🇦🇱' },
    'DZ' => { name: 'Algeria', iso2: 'DZ', iso3: 'DZA', flag: '🇩🇿' },
    'AS' => { name: 'American Samoa', iso2: 'AS', iso3: 'ASM', flag: '🇦🇸' },
    'AD' => { name: 'Andorra', iso2: 'AD', iso3: 'AND', flag: '🇦🇩' },
    'AO' => { name: 'Angola', iso2: 'AO', iso3: 'AGO', flag: '🇦🇴' },
    'AI' => { name: 'Anguilla', iso2: 'AI', iso3: 'AIA', flag: '🇦🇮' },
    'AQ' => { name: 'Antarctica', iso2: 'AQ', iso3: 'ATA', flag: '🇦🇶' },
    'AG' => { name: 'Antigua and Barbuda', iso2: 'AG', iso3: 'ATG', flag: '🇦🇬' },
    'AR' => { name: 'Argentina', iso2: 'AR', iso3: 'ARG', flag: '🇦🇷' },
    'AM' => { name: 'Armenia', iso2: 'AM', iso3: 'ARM', flag: '🇦🇲' },
    'AW' => { name: 'Aruba', iso2: 'AW', iso3: 'ABW', flag: '🇦🇼' },
    'AU' => { name: 'Australia', iso2: 'AU', iso3: 'AUS', flag: '🇦🇺' },
    'AT' => { name: 'Austria', iso2: 'AT', iso3: 'AUT', flag: '🇦🇹' },
    'AZ' => { name: 'Azerbaijan', iso2: 'AZ', iso3: 'AZE', flag: '🇦🇿' },
    'BS' => { name: 'Bahamas', iso2: 'BS', iso3: 'BHS', flag: '🇧🇸' },
    'BH' => { name: 'Bahrain', iso2: 'BH', iso3: 'BHR', flag: '🇧🇭' },
    'BD' => { name: 'Bangladesh', iso2: 'BD', iso3: 'BGD', flag: '🇧🇩' },
    'BB' => { name: 'Barbados', iso2: 'BB', iso3: 'BRB', flag: '🇧🇧' },
    'BY' => { name: 'Belarus', iso2: 'BY', iso3: 'BLR', flag: '🇧🇾' },
    'BE' => { name: 'Belgium', iso2: 'BE', iso3: 'BEL', flag: '🇧🇪' },
    'BZ' => { name: 'Belize', iso2: 'BZ', iso3: 'BLZ', flag: '🇧🇿' },
    'BJ' => { name: 'Benin', iso2: 'BJ', iso3: 'BEN', flag: '🇧🇯' },
    'BM' => { name: 'Bermuda', iso2: 'BM', iso3: 'BMU', flag: '🇧🇲' },
    'BT' => { name: 'Bhutan', iso2: 'BT', iso3: 'BTN', flag: '🇧🇹' },
    'BO' => { name: 'Bolivia', iso2: 'BO', iso3: 'BOL', flag: '🇧🇴' },
    'BA' => { name: 'Bosnia and Herzegovina', iso2: 'BA', iso3: 'BIH', flag: '🇧🇦' },
    'BW' => { name: 'Botswana', iso2: 'BW', iso3: 'BWA', flag: '🇧🇼' },
    'BR' => { name: 'Brazil', iso2: 'BR', iso3: 'BRA', flag: '🇧🇷' },
    'BN' => { name: 'Brunei Darussalam', iso2: 'BN', iso3: 'BRN', flag: '🇧🇳' },
    'BG' => { name: 'Bulgaria', iso2: 'BG', iso3: 'BGR', flag: '🇧🇬' },
    'BF' => { name: 'Burkina Faso', iso2: 'BF', iso3: 'BFA', flag: '🇧🇫' },
    'BI' => { name: 'Burundi', iso2: 'BI', iso3: 'BDI', flag: '🇧🇮' },
    'KH' => { name: 'Cambodia', iso2: 'KH', iso3: 'KHM', flag: '🇰🇭' },
    'CM' => { name: 'Cameroon', iso2: 'CM', iso3: 'CMR', flag: '🇨🇲' },
    'CA' => { name: 'Canada', iso2: 'CA', iso3: 'CAN', flag: '🇨🇦' },
    'CV' => { name: 'Cape Verde', iso2: 'CV', iso3: 'CPV', flag: '🇨🇻' },
    'KY' => { name: 'Cayman Islands', iso2: 'KY', iso3: 'CYM', flag: '🇰🇾' },
    'CF' => { name: 'Central African Republic', iso2: 'CF', iso3: 'CAF', flag: '🇨🇫' },
    'TD' => { name: 'Chad', iso2: 'TD', iso3: 'TCD', flag: '🇹🇩' },
    'CL' => { name: 'Chile', iso2: 'CL', iso3: 'CHL', flag: '🇨🇱' },
    'CN' => { name: 'China', iso2: 'CN', iso3: 'CHN', flag: '🇨🇳' },
    'CO' => { name: 'Colombia', iso2: 'CO', iso3: 'COL', flag: '🇨🇴' },
    'KM' => { name: 'Comoros', iso2: 'KM', iso3: 'COM', flag: '🇰🇲' },
    'CG' => { name: 'Congo', iso2: 'CG', iso3: 'COG', flag: '🇨🇬' },
    'CD' => { name: 'Congo, Democratic Republic of the', iso2: 'CD', iso3: 'COD', flag: '🇨🇩' },
    'CK' => { name: 'Cook Islands', iso2: 'CK', iso3: 'COK', flag: '🇨🇰' },
    'CR' => { name: 'Costa Rica', iso2: 'CR', iso3: 'CRI', flag: '🇨🇷' },
    'CI' => { name: 'Côte d\'Ivoire', iso2: 'CI', iso3: 'CIV', flag: '🇨🇮' },
    'HR' => { name: 'Croatia', iso2: 'HR', iso3: 'HRV', flag: '🇭🇷' },
    'CU' => { name: 'Cuba', iso2: 'CU', iso3: 'CUB', flag: '🇨🇺' },
    'CY' => { name: 'Cyprus', iso2: 'CY', iso3: 'CYP', flag: '🇨🇾' },
    'CZ' => { name: 'Czech Republic', iso2: 'CZ', iso3: 'CZE', flag: '🇨🇿' },
    'DK' => { name: 'Denmark', iso2: 'DK', iso3: 'DNK', flag: '🇩🇰' },
    'DJ' => { name: 'Djibouti', iso2: 'DJ', iso3: 'DJI', flag: '🇩🇯' },
    'DM' => { name: 'Dominica', iso2: 'DM', iso3: 'DMA', flag: '🇩🇲' },
    'DO' => { name: 'Dominican Republic', iso2: 'DO', iso3: 'DOM', flag: '🇩🇴' },
    'EC' => { name: 'Ecuador', iso2: 'EC', iso3: 'ECU', flag: '🇪🇨' },
    'EG' => { name: 'Egypt', iso2: 'EG', iso3: 'EGY', flag: '🇪🇬' },
    'SV' => { name: 'El Salvador', iso2: 'SV', iso3: 'SLV', flag: '🇸🇻' },
    'GQ' => { name: 'Equatorial Guinea', iso2: 'GQ', iso3: 'GNQ', flag: '🇬🇶' },
    'ER' => { name: 'Eritrea', iso2: 'ER', iso3: 'ERI', flag: '🇪🇷' },
    'EE' => { name: 'Estonia', iso2: 'EE', iso3: 'EST', flag: '🇪🇪' },
    'ET' => { name: 'Ethiopia', iso2: 'ET', iso3: 'ETH', flag: '🇪🇹' },
    'FK' => { name: 'Falkland Islands (Malvinas)', iso2: 'FK', iso3: 'FLK', flag: '🇫🇰' },
    'FO' => { name: 'Faroe Islands', iso2: 'FO', iso3: 'FRO', flag: '🇫🇴' },
    'FJ' => { name: 'Fiji', iso2: 'FJ', iso3: 'FJI', flag: '🇫🇯' },
    'FI' => { name: 'Finland', iso2: 'FI', iso3: 'FIN', flag: '🇫🇮' },
    'FR' => { name: 'France', iso2: 'FR', iso3: 'FRA', flag: '🇫🇷' },
    'GF' => { name: 'French Guiana', iso2: 'GF', iso3: 'GUF', flag: '🇬🇫' },
    'PF' => { name: 'French Polynesia', iso2: 'PF', iso3: 'PYF', flag: '🇵🇫' },
    'GA' => { name: 'Gabon', iso2: 'GA', iso3: 'GAB', flag: '🇬🇦' },
    'GM' => { name: 'Gambia', iso2: 'GM', iso3: 'GMB', flag: '🇬🇲' },
    'GE' => { name: 'Georgia', iso2: 'GE', iso3: 'GEO', flag: '🇬🇪' },
    'DE' => { name: 'Germany', iso2: 'DE', iso3: 'DEU', flag: '🇩🇪' },
    'GH' => { name: 'Ghana', iso2: 'GH', iso3: 'GHA', flag: '🇬🇭' },
    'GI' => { name: 'Gibraltar', iso2: 'GI', iso3: 'GIB', flag: '🇬🇮' },
    'GR' => { name: 'Greece', iso2: 'GR', iso3: 'GRC', flag: '🇬🇷' },
    'GL' => { name: 'Greenland', iso2: 'GL', iso3: 'GRL', flag: '🇬🇱' },
    'GD' => { name: 'Grenada', iso2: 'GD', iso3: 'GRD', flag: '🇬🇩' },
    'GP' => { name: 'Guadeloupe', iso2: 'GP', iso3: 'GLP', flag: '🇬🇵' },
    'GU' => { name: 'Guam', iso2: 'GU', iso3: 'GUM', flag: '🇬🇺' },
    'GT' => { name: 'Guatemala', iso2: 'GT', iso3: 'GTM', flag: '🇬🇹' },
    'GG' => { name: 'Guernsey', iso2: 'GG', iso3: 'GGY', flag: '🇬🇬' },
    'GN' => { name: 'Guinea', iso2: 'GN', iso3: 'GIN', flag: '🇬🇳' },
    'GW' => { name: 'Guinea-Bissau', iso2: 'GW', iso3: 'GNB', flag: '🇬🇼' },
    'GY' => { name: 'Guyana', iso2: 'GY', iso3: 'GUY', flag: '🇬🇾' },
    'HT' => { name: 'Haiti', iso2: 'HT', iso3: 'HTI', flag: '🇭🇹' },
    'VA' => { name: 'Holy See (Vatican City State)', iso2: 'VA', iso3: 'VAT', flag: '🇻🇦' },
    'HN' => { name: 'Honduras', iso2: 'HN', iso3: 'HND', flag: '🇭🇳' },
    'HK' => { name: 'Hong Kong', iso2: 'HK', iso3: 'HKG', flag: '🇭🇰' },
    'HU' => { name: 'Hungary', iso2: 'HU', iso3: 'HUN', flag: '🇭🇺' },
    'IS' => { name: 'Iceland', iso2: 'IS', iso3: 'ISL', flag: '🇮🇸' },
    'IN' => { name: 'India', iso2: 'IN', iso3: 'IND', flag: '🇮🇳' },
    'ID' => { name: 'Indonesia', iso2: 'ID', iso3: 'IDN', flag: '🇮🇩' },
    'IR' => { name: 'Iran, Islamic Republic of', iso2: 'IR', iso3: 'IRN', flag: '🇮🇷' },
    'IQ' => { name: 'Iraq', iso2: 'IQ', iso3: 'IRQ', flag: '🇮🇶' },
    'IE' => { name: 'Ireland', iso2: 'IE', iso3: 'IRL', flag: '🇮🇪' },
    'IM' => { name: 'Isle of Man', iso2: 'IM', iso3: 'IMN', flag: '🇮🇲' },
    'IL' => { name: 'Israel', iso2: 'IL', iso3: 'ISR', flag: '🇮🇱' },
    'IT' => { name: 'Italy', iso2: 'IT', iso3: 'ITA', flag: '🇮🇹' },
    'JM' => { name: 'Jamaica', iso2: 'JM', iso3: 'JAM', flag: '🇯🇲' },
    'JP' => { name: 'Japan', iso2: 'JP', iso3: 'JPN', flag: '🇯🇵' },
    'JE' => { name: 'Jersey', iso2: 'JE', iso3: 'JEY', flag: '🇯🇪' },
    'JO' => { name: 'Jordan', iso2: 'JO', iso3: 'JOR', flag: '🇯🇴' },
    'KZ' => { name: 'Kazakhstan', iso2: 'KZ', iso3: 'KAZ', flag: '🇰🇿' },
    'KE' => { name: 'Kenya', iso2: 'KE', iso3: 'KEN', flag: '🇰🇪' },
    'KI' => { name: 'Kiribati', iso2: 'KI', iso3: 'KIR', flag: '🇰🇮' },
    'KP' => { name: 'Korea, Democratic People\'s Republic of', iso2: 'KP', iso3: 'PRK', flag: '🇰🇵' },
    'KR' => { name: 'Korea, Republic of', iso2: 'KR', iso3: 'KOR', flag: '🇰🇷' },
    'KW' => { name: 'Kuwait', iso2: 'KW', iso3: 'KWT', flag: '🇰🇼' },
    'KG' => { name: 'Kyrgyzstan', iso2: 'KG', iso3: 'KGZ', flag: '🇰🇬' },
    'LA' => { name: 'Lao People\'s Democratic Republic', iso2: 'LA', iso3: 'LAO', flag: '🇱🇦' },
    'LV' => { name: 'Latvia', iso2: 'LV', iso3: 'LVA', flag: '🇱🇻' },
    'LB' => { name: 'Lebanon', iso2: 'LB', iso3: 'LBN', flag: '🇱🇧' },
    'LS' => { name: 'Lesotho', iso2: 'LS', iso3: 'LSO', flag: '🇱🇸' },
    'LR' => { name: 'Liberia', iso2: 'LR', iso3: 'LBR', flag: '🇱🇷' },
    'LY' => { name: 'Libya', iso2: 'LY', iso3: 'LBY', flag: '🇱🇾' },
    'LI' => { name: 'Liechtenstein', iso2: 'LI', iso3: 'LIE', flag: '🇱🇮' },
    'LT' => { name: 'Lithuania', iso2: 'LT', iso3: 'LTU', flag: '🇱🇹' },
    'LU' => { name: 'Luxembourg', iso2: 'LU', iso3: 'LUX', flag: '🇱🇺' },
    'MO' => { name: 'Macao', iso2: 'MO', iso3: 'MAC', flag: '🇲🇴' },
    'MK' => { name: 'North Macedonia', iso2: 'MK', iso3: 'MKD', flag: '🇲🇰' },
    'MG' => { name: 'Madagascar', iso2: 'MG', iso3: 'MDG', flag: '🇲🇬' },
    'MW' => { name: 'Malawi', iso2: 'MW', iso3: 'MWI', flag: '🇲🇼' },
    'MY' => { name: 'Malaysia', iso2: 'MY', iso3: 'MYS', flag: '🇲🇾' },
    'MV' => { name: 'Maldives', iso2: 'MV', iso3: 'MDV', flag: '🇲🇻' },
    'ML' => { name: 'Mali', iso2: 'ML', iso3: 'MLI', flag: '🇲🇱' },
    'MT' => { name: 'Malta', iso2: 'MT', iso3: 'MLT', flag: '🇲🇹' },
    'MH' => { name: 'Marshall Islands', iso2: 'MH', iso3: 'MHL', flag: '🇲🇭' },
    'MQ' => { name: 'Martinique', iso2: 'MQ', iso3: 'MTQ', flag: '🇲🇶' },
    'MR' => { name: 'Mauritania', iso2: 'MR', iso3: 'MRT', flag: '🇲🇷' },
    'MU' => { name: 'Mauritius', iso2: 'MU', iso3: 'MUS', flag: '🇲🇺' },
    'YT' => { name: 'Mayotte', iso2: 'YT', iso3: 'MYT', flag: '🇾🇹' },
    'MX' => { name: 'Mexico', iso2: 'MX', iso3: 'MEX', flag: '🇲🇽' },
    'FM' => { name: 'Micronesia, Federated States of', iso2: 'FM', iso3: 'FSM', flag: '🇫🇲' },
    'MD' => { name: 'Moldova, Republic of', iso2: 'MD', iso3: 'MDA', flag: '🇲🇩' },
    'MC' => { name: 'Monaco', iso2: 'MC', iso3: 'MCO', flag: '🇲🇨' },
    'MN' => { name: 'Mongolia', iso2: 'MN', iso3: 'MNG', flag: '🇲🇳' },
    'ME' => { name: 'Montenegro', iso2: 'ME', iso3: 'MNE', flag: '🇲🇪' },
    'MS' => { name: 'Montserrat', iso2: 'MS', iso3: 'MSR', flag: '🇲🇸' },
    'MA' => { name: 'Morocco', iso2: 'MA', iso3: 'MAR', flag: '🇲🇦' },
    'MZ' => { name: 'Mozambique', iso2: 'MZ', iso3: 'MOZ', flag: '🇲🇿' },
    'MM' => { name: 'Myanmar', iso2: 'MM', iso3: 'MMR', flag: '🇲🇲' },
    'NA' => { name: 'Namibia', iso2: 'NA', iso3: 'NAM', flag: '🇳🇦' },
    'NR' => { name: 'Nauru', iso2: 'NR', iso3: 'NRU', flag: '🇳🇷' },
    'NP' => { name: 'Nepal', iso2: 'NP', iso3: 'NPL', flag: '🇳🇵' },
    'NL' => { name: 'Netherlands', iso2: 'NL', iso3: 'NLD', flag: '🇳🇱' },
    'NC' => { name: 'New Caledonia', iso2: 'NC', iso3: 'NCL', flag: '🇳🇨' },
    'NZ' => { name: 'New Zealand', iso2: 'NZ', iso3: 'NZL', flag: '🇳🇿' },
    'NI' => { name: 'Nicaragua', iso2: 'NI', iso3: 'NIC', flag: '🇳🇮' },
    'NE' => { name: 'Niger', iso2: 'NE', iso3: 'NER', flag: '🇳🇪' },
    'NG' => { name: 'Nigeria', iso2: 'NG', iso3: 'NGA', flag: '🇳🇬' },
    'NU' => { name: 'Niue', iso2: 'NU', iso3: 'NIU', flag: '🇳🇺' },
    'NF' => { name: 'Norfolk Island', iso2: 'NF', iso3: 'NFK', flag: '🇳🇫' },
    'MP' => { name: 'Northern Mariana Islands', iso2: 'MP', iso3: 'MNP', flag: '🇲🇵' },
    'NO' => { name: 'Norway', iso2: 'NO', iso3: 'NOR', flag: '🇳🇴' },
    'OM' => { name: 'Oman', iso2: 'OM', iso3: 'OMN', flag: '🇴🇲' },
    'PK' => { name: 'Pakistan', iso2: 'PK', iso3: 'PAK', flag: '🇵🇰' },
    'PW' => { name: 'Palau', iso2: 'PW', iso3: 'PLW', flag: '🇵🇼' },
    'PS' => { name: 'Palestine, State of', iso2: 'PS', iso3: 'PSE', flag: '🇵🇸' },
    'PA' => { name: 'Panama', iso2: 'PA', iso3: 'PAN', flag: '🇵🇦' },
    'PG' => { name: 'Papua New Guinea', iso2: 'PG', iso3: 'PNG', flag: '🇵🇬' },
    'PY' => { name: 'Paraguay', iso2: 'PY', iso3: 'PRY', flag: '🇵🇾' },
    'PE' => { name: 'Peru', iso2: 'PE', iso3: 'PER', flag: '🇵🇪' },
    'PH' => { name: 'Philippines', iso2: 'PH', iso3: 'PHL', flag: '🇵🇭' },
    'PN' => { name: 'Pitcairn', iso2: 'PN', iso3: 'PCN', flag: '🇵🇳' },
    'PL' => { name: 'Poland', iso2: 'PL', iso3: 'POL', flag: '🇵🇱' },
    'PT' => { name: 'Portugal', iso2: 'PT', iso3: 'PRT', flag: '🇵🇹' },
    'PR' => { name: 'Puerto Rico', iso2: 'PR', iso3: 'PRI', flag: '🇵🇷' },
    'QA' => { name: 'Qatar', iso2: 'QA', iso3: 'QAT', flag: '🇶🇦' },
    'RE' => { name: 'Réunion', iso2: 'RE', iso3: 'REU', flag: '🇷🇪' },
    'RO' => { name: 'Romania', iso2: 'RO', iso3: 'ROU', flag: '🇷🇴' },
    'RU' => { name: 'Russian Federation', iso2: 'RU', iso3: 'RUS', flag: '🇷🇺' },
    'RW' => { name: 'Rwanda', iso2: 'RW', iso3: 'RWA', flag: '🇷🇼' },
    'BL' => { name: 'Saint Barthélemy', iso2: 'BL', iso3: 'BLM', flag: '🇧🇱' },
    'SH' => { name: 'Saint Helena, Ascension and Tristan da Cunha', iso2: 'SH', iso3: 'SHN', flag: '🇸🇭' },
    'KN' => { name: 'Saint Kitts and Nevis', iso2: 'KN', iso3: 'KNA', flag: '🇰🇳' },
    'LC' => { name: 'Saint Lucia', iso2: 'LC', iso3: 'LCA', flag: '🇱🇨' },
    'MF' => { name: 'Saint Martin (French part)', iso2: 'MF', iso3: 'MAF', flag: '🇲🇫' },
    'PM' => { name: 'Saint Pierre and Miquelon', iso2: 'PM', iso3: 'SPM', flag: '🇵🇲' },
    'VC' => { name: 'Saint Vincent and the Grenadines', iso2: 'VC', iso3: 'VCT', flag: '🇻🇨' },
    'WS' => { name: 'Samoa', iso2: 'WS', iso3: 'WSM', flag: '🇼🇸' },
    'SM' => { name: 'San Marino', iso2: 'SM', iso3: 'SMR', flag: '🇸🇲' },
    'ST' => { name: 'Sao Tome and Principe', iso2: 'ST', iso3: 'STP', flag: '🇸🇹' },
    'SA' => { name: 'Saudi Arabia', iso2: 'SA', iso3: 'SAU', flag: '🇸🇦' },
    'SN' => { name: 'Senegal', iso2: 'SN', iso3: 'SEN', flag: '🇸🇳' },
    'RS' => { name: 'Serbia', iso2: 'RS', iso3: 'SRB', flag: '🇷🇸' },
    'SC' => { name: 'Seychelles', iso2: 'SC', iso3: 'SYC', flag: '🇸🇨' },
    'SL' => { name: 'Sierra Leone', iso2: 'SL', iso3: 'SLE', flag: '🇸🇱' },
    'SG' => { name: 'Singapore', iso2: 'SG', iso3: 'SGP', flag: '🇸🇬' },
    'SX' => { name: 'Sint Maarten (Dutch part)', iso2: 'SX', iso3: 'SXM', flag: '🇸🇽' },
    'SK' => { name: 'Slovakia', iso2: 'SK', iso3: 'SVK', flag: '🇸🇰' },
    'SI' => { name: 'Slovenia', iso2: 'SI', iso3: 'SVN', flag: '🇸🇮' },
    'SB' => { name: 'Solomon Islands', iso2: 'SB', iso3: 'SLB', flag: '🇸🇧' },
    'SO' => { name: 'Somalia', iso2: 'SO', iso3: 'SOM', flag: '🇸🇴' },
    'ZA' => { name: 'South Africa', iso2: 'ZA', iso3: 'ZAF', flag: '🇿🇦' },
    'GS' => { name: 'South Georgia and the South Sandwich Islands', iso2: 'GS', iso3: 'SGS', flag: '🇬🇸' },
    'SS' => { name: 'South Sudan', iso2: 'SS', iso3: 'SSD', flag: '🇸🇸' },
    'ES' => { name: 'Spain', iso2: 'ES', iso3: 'ESP', flag: '🇪🇸' },
    'LK' => { name: 'Sri Lanka', iso2: 'LK', iso3: 'LKA', flag: '🇱🇰' },
    'SD' => { name: 'Sudan', iso2: 'SD', iso3: 'SDN', flag: '🇸🇩' },
    'SR' => { name: 'Suriname', iso2: 'SR', iso3: 'SUR', flag: '🇸🇷' },
    'SJ' => { name: 'Svalbard and Jan Mayen', iso2: 'SJ', iso3: 'SJM', flag: '🇸🇯' },
    'SE' => { name: 'Sweden', iso2: 'SE', iso3: 'SWE', flag: '🇸🇪' },
    'CH' => { name: 'Switzerland', iso2: 'CH', iso3: 'CHE', flag: '🇨🇭' },
    'SY' => { name: 'Syrian Arab Republic', iso2: 'SY', iso3: 'SYR', flag: '🇸🇾' },
    'TW' => { name: 'Taiwan, Province of China', iso2: 'TW', iso3: 'TWN', flag: '🇹🇼' },
    'TJ' => { name: 'Tajikistan', iso2: 'TJ', iso3: 'TJK', flag: '🇹🇯' },
    'TZ' => { name: 'Tanzania, United Republic of', iso2: 'TZ', iso3: 'TZA', flag: '🇹🇿' },
    'TH' => { name: 'Thailand', iso2: 'TH', iso3: 'THA', flag: '🇹🇭' },
    'TL' => { name: 'Timor-Leste', iso2: 'TL', iso3: 'TLS', flag: '🇹🇱' },
    'TG' => { name: 'Togo', iso2: 'TG', iso3: 'TGO', flag: '🇹🇬' },
    'TK' => { name: 'Tokelau', iso2: 'TK', iso3: 'TKL', flag: '🇹🇰' },
    'TO' => { name: 'Tonga', iso2: 'TO', iso3: 'TON', flag: '🇹🇴' },
    'TT' => { name: 'Trinidad and Tobago', iso2: 'TT', iso3: 'TTO', flag: '🇹🇹' },
    'TN' => { name: 'Tunisia', iso2: 'TN', iso3: 'TUN', flag: '🇹🇳' },
    'TR' => { name: 'Turkey', iso2: 'TR', iso3: 'TUR', flag: '🇹🇷' },
    'TM' => { name: 'Turkmenistan', iso2: 'TM', iso3: 'TKM', flag: '🇹🇲' },
    'TC' => { name: 'Turks and Caicos Islands', iso2: 'TC', iso3: 'TCA', flag: '🇹🇨' },
    'TV' => { name: 'Tuvalu', iso2: 'TV', iso3: 'TUV', flag: '🇹🇻' },
    'UG' => { name: 'Uganda', iso2: 'UG', iso3: 'UGA', flag: '🇺🇬' },
    'UA' => { name: 'Ukraine', iso2: 'UA', iso3: 'UKR', flag: '🇺🇦' },
    'AE' => { name: 'United Arab Emirates', iso2: 'AE', iso3: 'ARE', flag: '🇦🇪' },
    'GB' => { name: 'United Kingdom', iso2: 'GB', iso3: 'GBR', flag: '🇬🇧' },
    'US' => { name: 'United States', iso2: 'US', iso3: 'USA', flag: '🇺🇸' },
    'UM' => { name: 'United States Minor Outlying Islands', iso2: 'UM', iso3: 'UMI', flag: '🇺🇲' },
    'UY' => { name: 'Uruguay', iso2: 'UY', iso3: 'URY', flag: '🇺🇾' },
    'UZ' => { name: 'Uzbekistan', iso2: 'UZ', iso3: 'UZB', flag: '🇺🇿' },
    'VU' => { name: 'Vanuatu', iso2: 'VU', iso3: 'VUT', flag: '🇻🇺' },
    'VE' => { name: 'Venezuela, Bolivarian Republic of', iso2: 'VE', iso3: 'VEN', flag: '🇻🇪' },
    'VN' => { name: 'Viet Nam', iso2: 'VN', iso3: 'VNM', flag: '🇻🇳' },
    'VG' => { name: 'Virgin Islands, British', iso2: 'VG', iso3: 'VGB', flag: '🇻🇬' },
    'VI' => { name: 'Virgin Islands, U.S.', iso2: 'VI', iso3: 'VIR', flag: '🇻🇮' },
    'WF' => { name: 'Wallis and Futuna', iso2: 'WF', iso3: 'WLF', flag: '🇼🇫' },
    'EH' => { name: 'Western Sahara', iso2: 'EH', iso3: 'ESH', flag: '🇪🇭' },
    'YE' => { name: 'Yemen', iso2: 'YE', iso3: 'YEM', flag: '🇾🇪' },
    'ZM' => { name: 'Zambia', iso2: 'ZM', iso3: 'ZMB', flag: '🇿🇲' },
    'ZW' => { name: 'Zimbabwe', iso2: 'ZW', iso3: 'ZWE', flag: '🇿🇼' }
  }.freeze

  # Country name aliases and variations for better matching
  COUNTRY_ALIASES = {
    'Russia' => 'Russian Federation',
    'South Korea' => 'Korea, Republic of',
    'North Korea' => 'Korea, Democratic People\'s Republic of',
    'United States of America' => 'United States',
    'USA' => 'United States',
    'UK' => 'United Kingdom',
    'Britain' => 'United Kingdom',
    'Great Britain' => 'United Kingdom',
    'England' => 'United Kingdom',
    'Scotland' => 'United Kingdom',
    'Wales' => 'United Kingdom',
    'Northern Ireland' => 'United Kingdom',
    'Macedonia' => 'North Macedonia',
    'Czech Republic' => 'Czech Republic',
    'Czechia' => 'Czech Republic',
    'Vatican' => 'Holy See (Vatican City State)',
    'Vatican City' => 'Holy See (Vatican City State)',
    'Taiwan' => 'Taiwan, Province of China',
    'Hong Kong SAR' => 'Hong Kong',
    'Macao SAR' => 'Macao',
    'Moldova' => 'Moldova, Republic of',
    'Bolivia' => 'Bolivia',
    'Venezuela' => 'Venezuela, Bolivarian Republic of',
    'Iran' => 'Iran, Islamic Republic of',
    'Syria' => 'Syrian Arab Republic',
    'Tanzania' => 'Tanzania, United Republic of',
    'Laos' => 'Lao People\'s Democratic Republic',
    'Vietnam' => 'Viet Nam',
    'Palestine' => 'Palestine, State of',
    'Congo' => 'Congo',
    'Democratic Republic of Congo' => 'Congo, Democratic Republic of the',
    'DRC' => 'Congo, Democratic Republic of the',
    'Ivory Coast' => 'Côte d\'Ivoire',
    'Cape Verde' => 'Cape Verde',
    'East Timor' => 'Timor-Leste',
    'Burma' => 'Myanmar',
    'Swaziland' => 'Eswatini'
  }.freeze

  def self.iso_a3_from_a2(iso_a2)
    return nil if iso_a2.blank?

    country_data = COUNTRIES[iso_a2.upcase]
    country_data&.dig(:iso3)
  end

  def self.iso_codes_from_country_name(country_name)
    return [nil, nil] if country_name.blank?

    # Try exact match first
    country_data = find_country_by_name(country_name)
    return [country_data[:iso2], country_data[:iso3]] if country_data

    # Try aliases
    standard_name = COUNTRY_ALIASES[country_name]
    if standard_name
      country_data = find_country_by_name(standard_name)
      return [country_data[:iso2], country_data[:iso3]] if country_data
    end

    # Try case-insensitive match
    country_data = COUNTRIES.values.find { |data| data[:name].downcase == country_name.downcase }
    return [country_data[:iso2], country_data[:iso3]] if country_data

    # Try partial match (country name contains or is contained in a known name)
    country_data = COUNTRIES.values.find do |data|
      data[:name].downcase.include?(country_name.downcase) ||
        country_name.downcase.include?(data[:name].downcase)
    end
    return [country_data[:iso2], country_data[:iso3]] if country_data

    # No match found
    [nil, nil]
  end

  def self.fallback_codes_from_country_name(country_name)
    return [nil, nil] if country_name.blank?

    # First try to find proper ISO codes from country name
    iso_a2, iso_a3 = iso_codes_from_country_name(country_name)
    return [iso_a2, iso_a3] if iso_a2 && iso_a3

    # Only use character-based fallback as a last resort
    # This is still not ideal but better than nothing
    fallback_a2 = country_name[0..1].upcase
    fallback_a3 = country_name[0..2].upcase

    [fallback_a2, fallback_a3]
  end

  def self.standardize_country_name(country_name)
    return nil if country_name.blank?

    # Try exact match first
    country_data = find_country_by_name(country_name)
    return country_data[:name] if country_data

    # Try aliases
    standard_name = COUNTRY_ALIASES[country_name]
    return standard_name if standard_name

    # Try case-insensitive match
    country_data = COUNTRIES.values.find { |data| data[:name].downcase == country_name.downcase }
    return country_data[:name] if country_data

    # Try partial match
    country_data = COUNTRIES.values.find do |data|
      data[:name].downcase.include?(country_name.downcase) ||
        country_name.downcase.include?(data[:name].downcase)
    end
    return country_data[:name] if country_data

    nil
  end

  def self.country_flag(iso_a2)
    return nil if iso_a2.blank?

    country_data = COUNTRIES[iso_a2.upcase]
    country_data&.dig(:flag)
  end

  def self.country_by_iso2(iso_a2)
    return nil if iso_a2.blank?

    COUNTRIES[iso_a2.upcase]
  end

  def self.country_by_name(country_name)
    return nil if country_name.blank?

    find_country_by_name(country_name) ||
      find_country_by_name(COUNTRY_ALIASES[country_name]) ||
      COUNTRIES.values.find { |data| data[:name].downcase == country_name.downcase }
  end

  def self.all_countries
    COUNTRIES.values
  end

  def self.find_country_by_name(name)
    return nil if name.blank?

    COUNTRIES.values.find { |data| data[:name] == name }
  end
end
