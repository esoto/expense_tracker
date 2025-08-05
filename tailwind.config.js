const defaultTheme = require('tailwindcss/defaultTheme')

module.exports = {
  content: [
    './public/*.html',
    './app/helpers/**/*.rb',
    './app/javascript/**/*.js',
    './app/views/**/*.{erb,haml,html,slim}'
  ],
  theme: {
    extend: {
      colors: {
        // Financial Confidence Color Palette
        primary: {
          DEFAULT: '#0F766E', // teal-700
          50: '#F0FDFA',      // teal-50
          100: '#CCFBF1',     // teal-100
          200: '#99F6E4',     // teal-200
          300: '#5EEAD4',     // teal-300
          400: '#2DD4BF',     // teal-400
          500: '#14B8A6',     // teal-500
          600: '#0D9488',     // teal-600
          700: '#0F766E',     // teal-700
          800: '#115E59',     // teal-800
          900: '#134E4A',     // teal-900
        },
        secondary: {
          DEFAULT: '#D97706', // amber-600
          50: '#FFFBEB',      // amber-50
          100: '#FEF3C7',     // amber-100
          200: '#FDE68A',     // amber-200
          300: '#FCD34D',     // amber-300
          400: '#FBBF24',     // amber-400
          500: '#F59E0B',     // amber-500
          600: '#D97706',     // amber-600
          700: '#B45309',     // amber-700
          800: '#92400E',     // amber-800
          900: '#78350F',     // amber-900
        },
        accent: {
          DEFAULT: '#FB7185', // rose-400
          50: '#FFF1F2',      // rose-50
          100: '#FFE4E6',     // rose-100
          200: '#FECDD3',     // rose-200
          300: '#FDA4AF',     // rose-300
          400: '#FB7185',     // rose-400
          500: '#F43F5E',     // rose-500
          600: '#E11D48',     // rose-600
          700: '#BE123C',     // rose-700
          800: '#9F1239',     // rose-800
          900: '#881337',     // rose-900
        },
        // Status colors mapped to our palette
        success: {
          DEFAULT: '#10B981', // emerald-500
          50: '#ECFDF5',      // emerald-50
          100: '#D1FAE5',     // emerald-100
          200: '#A7F3D0',     // emerald-200
          300: '#6EE7B7',     // emerald-300
          400: '#34D399',     // emerald-400
          500: '#10B981',     // emerald-500
          600: '#059669',     // emerald-600
          700: '#047857',     // emerald-700
          800: '#065F46',     // emerald-800
          900: '#064E3B',     // emerald-900
        },
        warning: {
          DEFAULT: '#D97706', // amber-600 (same as secondary)
          light: '#FFFBEB',   // amber-50
          dark: '#B45309',    // amber-700
        },
        error: {
          DEFAULT: '#E11D48', // rose-600
          light: '#FFF1F2',   // rose-50
          dark: '#BE123C',    // rose-700
        },
        // Ensure we override any blue references
        blue: {
          DEFAULT: '#0F766E', // Redirect to teal-700
          50: '#F0FDFA',
          100: '#CCFBF1',
          200: '#99F6E4',
          300: '#5EEAD4',
          400: '#2DD4BF',
          500: '#14B8A6',
          600: '#0F766E',
          700: '#115E59',
          800: '#134E4A',
          900: '#0A4F48',
        }
      },
      fontFamily: {
        sans: ['Inter var', ...defaultTheme.fontFamily.sans],
      },
      // Ensure consistent shadows
      boxShadow: {
        'sm': '0 1px 2px 0 rgb(0 0 0 / 0.05)',
        'DEFAULT': '0 1px 3px 0 rgb(0 0 0 / 0.1), 0 1px 2px -1px rgb(0 0 0 / 0.1)',
        'md': '0 4px 6px -1px rgb(0 0 0 / 0.1), 0 2px 4px -2px rgb(0 0 0 / 0.1)',
        'lg': '0 10px 15px -3px rgb(0 0 0 / 0.1), 0 4px 6px -4px rgb(0 0 0 / 0.1)',
        'xl': '0 20px 25px -5px rgb(0 0 0 / 0.1), 0 8px 10px -6px rgb(0 0 0 / 0.1)',
      },
    },
  },
  plugins: [
    require('@tailwindcss/forms'),
    require('@tailwindcss/typography'),
    require('@tailwindcss/container-queries'),
  ]
}