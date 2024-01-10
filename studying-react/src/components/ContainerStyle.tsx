import React from "react"

interface Props {
    style: React.CSSProperties;
}

function ContainerStyle({style} : Props) {
  return (
    <div style={style}>ContainerStyle</div>
  )
}

export default ContainerStyle