import React from 'react';
import { Link } from 'react-router-dom';

export const NavBar = () => {
  return (
    <nav>
      <ul>
        <li>
          <Link to="/">Home</Link>
        </li>
        <li>
          <Link to="/list-group">List-Group</Link>
        </li>
      </ul>
    </nav>
  );
};
