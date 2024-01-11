import React, { createContext } from 'react';
import { theme } from './theme';

type ThemeContextThemeProviderProps = {
  children: React.ReactNode;
};

export const ThemeContext = createContext(theme); //Crea un contexto con el objeto que le pasamos

// prettier-ignore
export const ThemeContextProvider = ({children}: ThemeContextThemeProviderProps) => {
  return (
    <ThemeContext.Provider value={theme}>{children}</ThemeContext.Provider>
  );
};
